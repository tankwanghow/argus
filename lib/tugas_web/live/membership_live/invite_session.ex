defmodule TugasWeb.MembershipLive.InviteSession do
  use TugasWeb, :live_view

  alias Tugas.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md text-center">
        <.header>
          Invite {@role}s
          <:subtitle>
            Scan to join {@current_scope.entity.name}. Closes automatically in 30 min.
          </:subtitle>
        </.header>

        <%= if @closed do %>
          <p class="alert alert-info mt-6">Session closed.</p>
          <.link navigate={~p"/entities/#{@current_scope.entity.slug}/members"} class="btn mt-4">
            Back to members
          </.link>
        <% else %>
          <div class="mt-6 flex justify-center">{raw(@qr)}</div>
          <p class="mt-2 break-all text-sm text-base-content/70">{@link}</p>

          <button phx-click="close" class="btn btn-error btn-soft mt-4" phx-disable-with="Closing...">
            Close session
          </button>

          <div class="mt-8 text-left">
            <p class="font-semibold">Joined so far ({@count})</p>
            <ul id="roster" phx-update="stream" class="mt-2 space-y-1">
              <li :for={{id, m} <- @streams.roster} id={id} class="badge badge-soft">
                {m.user.username || m.user.email}
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"role" => role}, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      case Entities.open_invite_session(scope, role) do
        {:ok, invitation} ->
          Phoenix.PubSub.subscribe(Tugas.PubSub, "entity:#{scope.entity.id}:members")

          link = url(~p"/invitations/#{Entities.Invitation.encode_token(invitation.token)}")

          {:ok,
           socket
           |> assign(
             role: role,
             invitation: invitation,
             link: link,
             qr: TugasWeb.QR.svg(link),
             closed: false,
             count: 0
           )
           |> stream(:roster, [])}

        _ ->
          {:ok,
           socket
           |> put_flash(:error, "You can't open an invite session.")
           |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/members")}
      end
    else
      {:ok,
       assign(socket,
         role: role,
         invitation: nil,
         link: "",
         qr: "",
         closed: false,
         count: 0
       )
       |> stream(:roster, [])}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    Entities.close_invite_session(socket.assigns.current_scope, socket.assigns.invitation.id)
    {:noreply, assign(socket, :closed, true)}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:member_joined, membership}, socket) do
    {:noreply,
     socket
     |> stream_insert(:roster, membership, at: 0)
     |> update(:count, &(&1 + 1))}
  end
end
