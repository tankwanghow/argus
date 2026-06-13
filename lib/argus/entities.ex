defmodule Argus.Entities do
  @moduledoc """
  Entities (tenants), memberships, and invitations.
  """

  import Ecto.Query, warn: false

  alias Argus.Accounts.{Scope, User}
  alias Argus.Entities.{Entity, Invitation, Membership}
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

  def seats_available?(%Entity{} = entity) do
    count =
      Membership
      |> where([m], m.entity_id == ^entity.id and not is_nil(m.accepted_at))
      |> Repo.aggregate(:count)

    count < entity.seat_limit
  end

  def invite_member(%Scope{user: inviter, entity: entity}, email, role) do
    with true <- seats_available?(entity),
         {:ok, invitation} <- insert_invitation(entity, inviter, email, role) do
      {:ok, invitation}
    else
      false -> {:error, :seat_limit_reached}
      {:error, changeset} -> {:error, changeset}
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

  defp fetch_pending_invitation(token) do
    case Repo.get_by(Invitation, token: token) do
      %Invitation{accepted_at: nil, expires_at: expires_at} = invitation ->
        if DateTime.compare(DateTime.utc_now(:second), expires_at) == :lt do
          {:ok, Repo.preload(invitation, :entity)}
        else
          {:error, :expired}
        end

      %Invitation{} ->
        {:error, :already_accepted}

      nil ->
        {:error, :not_found}
    end
  end

  defp accept_invitation_multi(user, %Invitation{} = invitation) do
    now = DateTime.utc_now(:second)

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
    |> Ecto.Multi.update(:invitation, Invitation.changeset(invitation, %{accepted_at: now}))
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} -> {:ok, membership}
      {:error, :membership, changeset, _} -> {:error, changeset}
      {:error, :invitation, changeset, _} -> {:error, changeset}
    end
  end

  defp first_entity_for_user?(%User{} = user) do
    Membership
    |> where([m], m.user_id == ^user.id)
    |> Repo.aggregate(:count) == 0
  end
end
