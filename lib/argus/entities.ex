defmodule Argus.Entities do
  @moduledoc """
  Entities (tenants), memberships, and invitations.
  """

  import Ecto.Query, warn: false

  alias Argus.Accounts.{Scope, User}
  alias Argus.Accounts.UserNotifier
  alias Argus.Authorization
  alias Argus.Entities.{Entity, Invitation, Membership}
  alias Argus.Obligations.SampleTypes
  alias Argus.Repo

  @invitation_validity_days 7

  def change_entity(%Entity{} = entity, attrs \\ %{}) do
    Entity.changeset(entity, attrs)
  end

  def create_entity(%Scope{user: %User{} = user}, attrs) do
    now = DateTime.utc_now(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:entity, Entity.changeset(%Entity{}, attrs))
    |> Ecto.Multi.insert(:membership, fn %{entity: entity} ->
      %Membership{
        user_id: user.id,
        entity_id: entity.id,
        role: "admin",
        accepted_at: now,
        is_default: first_entity_for_user?(user)
      }
      |> Membership.changeset(%{})
    end)
    |> Ecto.Multi.run(:sample_types, fn _repo, %{entity: entity} ->
      SampleTypes.seed_for_entity(entity.id)
      {:ok, :seeded}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{entity: entity}} -> {:ok, entity}
      {:error, :entity, changeset, _} -> {:error, changeset}
      {:error, :membership, changeset, _} -> {:error, changeset}
    end
  end

  def list_user_entities(%User{} = user) do
    Entity
    |> join(:inner, [e], m in Membership, on: m.entity_id == e.id)
    |> where([e, m], m.user_id == ^user.id and is_nil(e.deleted_at))
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end

  def list_entity_members(%Entity{} = entity) do
    Membership
    |> join(:inner, [m], u in User, on: u.id == m.user_id)
    |> where([m], m.entity_id == ^entity.id and not is_nil(m.accepted_at))
    |> order_by([m, u], asc: u.email)
    |> select([m, u], {u, m})
    |> Repo.all()
  end

  def list_entity_memberships(%User{} = user) do
    Membership
    |> join(:inner, [m], e in Entity, on: e.id == m.entity_id)
    |> where([m, e], m.user_id == ^user.id and is_nil(e.deleted_at))
    |> order_by([m, e], asc: e.name)
    |> select([m, e], {e, m})
    |> Repo.all()
  end

  def get_entity_by_slug_for_user!(slug, %User{} = user) do
    Entity
    |> join(:inner, [e], m in Membership, on: m.entity_id == e.id)
    |> where([e, m], e.slug == ^slug and m.user_id == ^user.id and is_nil(e.deleted_at))
    |> Repo.one!()
  end

  def get_membership!(%User{} = user, %Entity{} = entity) do
    Membership
    |> where([m], m.user_id == ^user.id and m.entity_id == ^entity.id)
    |> Repo.one!()
  end

  def get_membership_in_entity!(%Entity{} = entity, id) do
    Membership
    |> where([m], m.id == ^id and m.entity_id == ^entity.id)
    |> Repo.one!()
  end

  def seats_available?(%Entity{} = entity) do
    count =
      Membership
      |> where([m], m.entity_id == ^entity.id and not is_nil(m.accepted_at))
      |> Repo.aggregate(:count)

    count < entity.seat_limit
  end

  @doc """
  Creates a pending invitation. When `url_fun` is given, also emails the
  invitee a link to accept it; `url_fun.(encoded_token)` builds the URL.
  """
  def invite_member(%Scope{user: inviter, entity: entity} = scope, email, role, url_fun \\ nil)
      when is_function(url_fun, 1) or is_nil(url_fun) do
    cond do
      not Authorization.can?(scope, :manage_entity) ->
        :not_authorise

      not seats_available?(entity) ->
        {:error, :seat_limit_reached}

      true ->
        email = if email in [nil, ""], do: nil, else: email

        with {:ok, invitation} <- insert_invitation(entity, inviter, email, role) do
          if url_fun && invitation.email do
            UserNotifier.deliver_entity_invitation(
              invitation.email,
              entity.name,
              invitation.role,
              url_fun.(Invitation.encode_token(invitation.token))
            )
          end

          {:ok, invitation}
        end
    end
  end

  @doc """
  Opens a reusable, admin-supervised invite session for `role` ("manager" or
  "member"). Auto-expires 30 minutes from now; close early with
  `close_invite_session/2`.
  """
  def open_invite_session(%Scope{user: inviter, entity: entity} = scope, role) do
    cond do
      not Authorization.can?(scope, :manage_entity) ->
        :not_authorise

      role not in ["manager", "member"] ->
        {:error, :invalid_role}

      true ->
        token = :crypto.strong_rand_bytes(32)
        expires_at = DateTime.add(DateTime.utc_now(:second), 30 * 60, :second)

        %Invitation{entity_id: entity.id, invited_by_id: inviter.id}
        |> Invitation.changeset(%{
          role: role,
          token: token,
          expires_at: expires_at,
          reusable: true
        })
        |> Repo.insert()
    end
  end

  @doc """
  Closes a reusable invite session (admin-only). Stamps `closed_at`.
  """
  def close_invite_session(%Scope{} = scope, invitation_id) do
    if Authorization.can?(scope, :manage_entity) do
      case Repo.get_by(Invitation, id: invitation_id, entity_id: scope.entity.id, reusable: true) do
        nil ->
          {:error, :not_found}

        invitation ->
          invitation
          |> Invitation.changeset(%{closed_at: DateTime.utc_now(:second)})
          |> Repo.update()
      end
    else
      :not_authorise
    end
  end

  @doc """
  Pending (un-accepted, un-expired) invitations for an entity.
  """
  def list_pending_invitations(%Entity{} = entity) do
    now = DateTime.utc_now(:second)

    Invitation
    |> where([i], i.entity_id == ^entity.id and is_nil(i.accepted_at) and i.expires_at > ^now)
    |> order_by([i], asc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Revokes a pending invitation. Admin-only (`:manage_entity`).
  """
  def revoke_invitation(%Scope{} = scope, invitation_id) do
    cond do
      not Authorization.can?(scope, :manage_entity) ->
        :not_authorise

      true ->
        case fetch_revokable_invitation(scope.entity, invitation_id) do
          nil -> {:error, :not_found}
          invitation -> Repo.delete(invitation)
        end
    end
  end

  @doc """
  Changes a member's role. Admin-only (`:manage_entity`); the membership must
  belong to the scope's entity. Role changes don't consume a seat.
  """
  def update_member_role(%Scope{} = scope, %Membership{} = membership, role) do
    if Authorization.can?(scope, :manage_entity) and membership.entity_id == scope.entity.id do
      membership
      |> Membership.changeset(%{role: role})
      |> Repo.update()
    else
      :not_authorise
    end
  end

  @doc """
  Fetches a pending, non-expired invitation by its URL-safe encoded token,
  with `:entity` preloaded. Returns `:error` for malformed/unknown/expired/
  already-accepted tokens.
  """
  def get_invitation_by_encoded_token(encoded) when is_binary(encoded) do
    with {:ok, token} <- Invitation.decode_token(encoded),
         {:ok, invitation} <- fetch_pending_invitation(token) do
      {:ok, invitation}
    else
      _ -> :error
    end
  end

  def accept_invitation(%User{} = user, token) when is_binary(token) do
    with {:ok, invitation} <- fetch_pending_invitation(token),
         true <- seats_available?(invitation.entity),
         {:ok, membership} <- accept_invitation_multi(user, invitation) do
      {:ok, membership}
    else
      false -> {:error, :seat_limit_reached}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_invitation(entity, inviter, email, role) do
    token = :crypto.strong_rand_bytes(32)
    expires_at = DateTime.utc_now(:second) |> DateTime.add(@invitation_validity_days, :day)

    %Invitation{
      entity_id: entity.id,
      invited_by_id: inviter.id
    }
    |> Invitation.changeset(%{
      email: email,
      role: role,
      token: token,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  defp fetch_revokable_invitation(%Entity{} = entity, invitation_id) do
    Invitation
    |> where([i], i.id == ^invitation_id and i.entity_id == ^entity.id and is_nil(i.accepted_at))
    |> Repo.one()
  end

  defp fetch_pending_invitation(token) do
    case Repo.get_by(Invitation, token: token) do
      %Invitation{} = invitation -> validate_invitation_live(invitation)
      nil -> {:error, :not_found}
    end
  end

  defp validate_invitation_live(%Invitation{reusable: true} = inv) do
    cond do
      not is_nil(inv.closed_at) -> {:error, :closed}
      invitation_expired?(inv) -> {:error, :expired}
      true -> {:ok, Repo.preload(inv, :entity)}
    end
  end

  defp validate_invitation_live(%Invitation{reusable: false} = inv) do
    cond do
      not is_nil(inv.accepted_at) -> {:error, :already_accepted}
      invitation_expired?(inv) -> {:error, :expired}
      true -> {:ok, Repo.preload(inv, :entity)}
    end
  end

  defp invitation_expired?(%Invitation{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(:second), expires_at) != :lt
  end

  defp accept_invitation_multi(user, %Invitation{} = invitation) do
    now = DateTime.utc_now(:second)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:membership, fn _ ->
        %Membership{
          user_id: user.id,
          entity_id: invitation.entity_id,
          role: invitation.role,
          invited_by_id: invitation.invited_by_id,
          accepted_at: now,
          is_default: first_entity_for_user?(user)
        }
        |> Membership.changeset(%{})
      end)

    multi =
      if invitation.reusable do
        multi
      else
        Ecto.Multi.update(
          multi,
          :invitation,
          Invitation.changeset(invitation, %{accepted_at: now})
        )
      end

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} ->
        membership = Repo.preload(membership, :user)

        Phoenix.PubSub.broadcast(
          Argus.PubSub,
          "entity:#{invitation.entity_id}:members",
          {:member_joined, membership}
        )

        {:ok, membership}

      {:error, :membership, %Ecto.Changeset{} = changeset, _} ->
        if Enum.any?(changeset.errors, fn {_f, {_m, opts}} -> opts[:constraint] == :unique end) do
          {:ok, :already_member}
        else
          {:error, changeset}
        end

      {:error, :invitation, changeset, _} ->
        {:error, changeset}
    end
  end

  defp first_entity_for_user?(%User{} = user) do
    Membership
    |> where([m], m.user_id == ^user.id)
    |> Repo.aggregate(:count) == 0
  end
end
