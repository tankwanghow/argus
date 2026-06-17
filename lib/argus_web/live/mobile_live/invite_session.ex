defmodule ArgusWeb.MobileLive.InviteSession do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:more}>
      <div class="flex flex-col h-full">
        <div class="flex items-center justify-between gap-2 px-4 py-3 border-b border-base-200">
          <.link navigate={~p"/m/#{@current_scope.entity.slug}"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left-micro" class="size-4" /> Back
          </.link>
          <h1 class="font-semibold text-sm">Invite members</h1>
          <div class="flex gap-1">
            <.link
              :for={r <- ~w[manager member]}
              navigate={~p"/m/#{@current_scope.entity.slug}/invite-session/#{r}"}
              class={[
                "btn btn-xs capitalize",
                @role == r && "btn-primary",
                @role != r && "btn-ghost"
              ]}
            >
              {r}
            </.link>
          </div>
        </div>

        <%= if @closed do %>
          <div class="flex flex-col items-center justify-center flex-1 gap-4 px-6 text-center">
            <.icon name="hero-check-circle" class="size-12 text-success" />
            <p class="font-semibold">Session closed.</p>
            <.link navigate={~p"/m/#{@current_scope.entity.slug}"} class="btn btn-primary">
              Back to dashboard
            </.link>
          </div>
        <% else %>
          <div class="flex flex-col items-center gap-3 px-4 pt-4 flex-shrink-0">
            <div id="invite-qr" class="bg-white p-3 rounded-xl">{raw(@qr)}</div>
            <p class="text-sm text-base-content/60 text-center">
              Show to members to scan
            </p>
            <button
              phx-click="close"
              class="btn btn-error btn-soft btn-sm"
              phx-disable-with="Closing..."
            >
              Close session
            </button>
          </div>

          <div class="flex-1 overflow-y-auto px-4 pt-4">
            <p class="text-sm font-semibold mb-2">
              Joined so far ({@count})
            </p>
            <ul id="roster" phx-update="stream" class="space-y-2">
              <li
                :for={{id, m} <- @streams.roster}
                id={id}
                class="flex items-center gap-3 p-2 rounded-lg bg-base-200"
              >
                <div class="size-8 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold select-none">
                  {m.user |> display_name() |> String.upcase() |> String.first()}
                </div>
                <span class="text-sm">{display_name(m.user)}</span>
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(%{"role" => role}, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      not Authorization.can?(scope, :manage_entity) ->
        {:ok,
         socket
         |> put_flash(:error, "Not authorized.")
         |> push_navigate(to: ~p"/m/#{scope.entity.slug}")}

      connected?(socket) ->
        case Entities.open_invite_session(scope, role) do
          {:ok, invitation} ->
            Phoenix.PubSub.subscribe(Argus.PubSub, "entity:#{scope.entity.id}:members")

            encoded = Entities.Invitation.encode_token(invitation.token)
            link = url(~p"/invitations/#{encoded}")

            {:ok,
             socket
             |> assign(
               role: role,
               invitation: invitation,
               link: link,
               qr: ArgusWeb.QR.svg(link),
               closed: false,
               count: 0
             )
             |> stream(:roster, [])}

          _ ->
            {:ok,
             socket
             |> put_flash(:error, "Could not open invite session.")
             |> push_navigate(to: ~p"/m/#{scope.entity.slug}")}
        end

      true ->
        {:ok,
         assign(socket, role: role, invitation: nil, link: "", qr: "", closed: false, count: 0)
         |> stream(:roster, [])}
    end
  end

  @impl true
  def handle_event("close", _, socket) do
    if socket.assigns.invitation do
      Entities.close_invite_session(socket.assigns.current_scope, socket.assigns.invitation.id)
    end

    {:noreply, assign(socket, :closed, true)}
  end

  @impl true
  def handle_info({:member_joined, membership}, socket) do
    {:noreply,
     socket
     |> stream_insert(:roster, membership, at: 0)
     |> update(:count, &(&1 + 1))}
  end

  defp display_name(%{username: u}) when is_binary(u) and u != "", do: u
  defp display_name(%{email: e}), do: e || "?"
end
