defmodule TugasWeb.MembershipLive.IndexHelpers do
  @moduledoc false

  use TugasWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Tugas.Authorization
  alias Tugas.Entities

  @roles [
    {"Admin", "admin"},
    {"Manager", "manager"},
    {"Coordinator", "coordinator"},
    {"Member", "member"}
  ]

  def roles, do: @roles

  def mount_assigns(socket) do
    socket
    |> assign(:can_manage?, Authorization.can?(socket.assigns.current_scope, :manage_entity))
    |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
    |> assign(:last_invite_link, nil)
    |> assign(:disabling, nil)
    |> load_members()
  end

  def handle_change_role(socket, %{"membership_id" => id, "role" => role}) do
    scope = socket.assigns.current_scope
    membership = Entities.get_membership_in_entity!(scope.entity, id)

    case Entities.update_member_role(scope, membership, role) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Role updated.")
         |> assign(:last_invite_link, nil)
         |> load_members()}

      :not_authorise ->
        {:error, put_flash(socket, :error, "Not authorized.")}

      {:error, _} ->
        {:error, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_revoke_invitation(socket, %{"invitation_id" => invitation_id}) do
    scope = socket.assigns.current_scope

    case Entities.revoke_invitation(scope, invitation_id) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Invitation revoked.")
         |> assign(:last_invite_link, nil)
         |> load_members()}

      :not_authorise ->
        {:error, put_flash(socket, :error, "Not authorized.")}

      {:error, :not_found} ->
        {:error, put_flash(socket, :error, "Invitation not found.")}
    end
  end

  def handle_invite(socket, %{"invite" => %{"email" => email, "role" => role}}) do
    scope = socket.assigns.current_scope
    url_fun = fn encoded -> url(~p"/invitations/#{encoded}") end

    case Entities.invite_member(scope, email, role, url_fun) do
      {:ok, invitation} ->
        link = url(~p"/invitations/#{Entities.Invitation.encode_token(invitation.token)}")

        {:ok,
         socket
         |> put_flash(:info, invite_flash(invitation))
         |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
         |> assign(:last_invite_link, link)
         |> load_members()}

      {:error, :seat_limit_reached} ->
        {:error, put_flash(socket, :error, "Seat limit reached — no seats available.")}

      :not_authorise ->
        {:error, put_flash(socket, :error, "Not authorized.")}

      {:error, %Ecto.Changeset{}} ->
        {:error, put_flash(socket, :error, "Check the email address and try again.")}
    end
  end

  @doc "Opens the disable-confirmation modal for a member, carrying its assignment counts."
  def handle_request_disable(socket, %{"membership_id" => id}) do
    case Enum.find(socket.assigns.members, fn {_u, m, _c} -> m.id == id end) do
      {user, membership, counts} ->
        {:noreply,
         assign(socket, :disabling, %{user: user, membership: membership, counts: counts})}

      nil ->
        {:noreply, socket}
    end
  end

  @doc "Commits the pending disable (auto-unassigns the member's live work)."
  def handle_confirm_disable(socket) do
    scope = socket.assigns.current_scope

    case socket.assigns.disabling do
      %{membership: membership} ->
        case Entities.disable_member(scope, membership) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Member disabled and their live work unassigned.")
             |> assign(:disabling, nil)
             |> assign(:last_invite_link, nil)
             |> load_members()}

          {:error, :cannot_disable_self} ->
            {:noreply,
             socket
             |> put_flash(:error, "You cannot disable yourself.")
             |> assign(:disabling, nil)}

          {:error, :last_admin} ->
            {:noreply,
             socket
             |> put_flash(:error, "You cannot disable the last active admin.")
             |> assign(:disabling, nil)}

          :not_authorise ->
            {:noreply, socket |> put_flash(:error, "Not authorized.") |> assign(:disabling, nil)}

          _ ->
            {:noreply,
             socket |> put_flash(:error, "Could not disable member.") |> assign(:disabling, nil)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @doc "Re-enables a disabled member (re-checks the seat limit)."
  def handle_enable_member(socket, %{"membership_id" => id}) do
    scope = socket.assigns.current_scope
    membership = Entities.get_membership_in_entity!(scope.entity, id)

    case Entities.enable_member(scope, membership) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Member re-enabled.") |> load_members()}

      {:error, :seat_limit_reached} ->
        {:noreply, put_flash(socket, :error, "Seat limit reached — free a seat first.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not enable member.")}
    end
  end

  @doc "Closes the disable-confirmation modal (shell Escape contract)."
  def close_disable_modal(socket), do: assign(socket, :disabling, nil)

  @doc "Total live assignments (primary + collaborations) for a counts map."
  def assignment_total(%{primary: p, collaborations: c}), do: p + c

  @doc "Human summary of a member's live assignments, e.g. \"2 duties · 1 collaboration\"."
  def assignment_summary(%{primary: p, collaborations: c}) do
    [pluralize(p, "duty", "duties"), pluralize(c, "collaboration", "collaborations")]
    |> Enum.join(" · ")
  end

  defp pluralize(1, singular, _plural), do: "1 #{singular}"
  defp pluralize(n, _singular, plural), do: "#{n} #{plural}"

  def handle_result({:ok, socket}), do: {:noreply, socket}
  def handle_result({:error, socket}), do: {:noreply, socket}

  defp invite_flash(%{email: nil}), do: "Invitation created. Share the link below."
  defp invite_flash(%{email: email}), do: "Invitation sent to #{email}."

  defp load_members(socket) do
    entity = socket.assigns.current_scope.entity
    members = Entities.list_member_administration(entity)
    seats_used = Enum.count(members, fn {_u, m, _c} -> is_nil(m.disabled_at) end)

    socket
    |> assign(:members, members)
    |> assign(:seats_used, seats_used)
    |> assign(:pending, Entities.list_pending_invitations(entity))
  end
end
