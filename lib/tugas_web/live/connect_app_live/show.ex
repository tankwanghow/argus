defmodule TugasWeb.ConnectAppLive.Show do
  use TugasWeb, :live_view

  alias Tugas.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_pairing(socket)}
  end

  defp assign_pairing(socket) do
    scope = socket.assigns.current_scope
    code = Accounts.create_pairing_code(scope.user, scope.entity)

    payload =
      Jason.encode!(%{
        host: TugasWeb.Endpoint.url(),
        entity_slug: scope.entity.slug,
        pairing_code: code
      })

    qr_svg = payload |> EQRCode.encode() |> EQRCode.svg(width: 240)

    socket
    |> assign(:pairing_code, code)
    |> assign(:qr_svg, qr_svg)
    |> assign(:tokens, Accounts.list_api_tokens(scope.user))
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    {:noreply, assign_pairing(socket)}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    Accounts.delete_api_token(socket.assigns.current_scope.user, id)

    {:noreply,
     assign(socket, :tokens, Accounts.list_api_tokens(socket.assigns.current_scope.user))}
  end

  # Shell-Escape contract: this page has no modals.
  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-md mx-auto space-y-6">
        <h1 class="text-xl font-semibold">Connect mobile app</h1>
        <p class="text-sm opacity-70">
          Scan this code in the Tugas Capture app within 5 minutes to pair it to <span class="font-medium">{@current_scope.entity.name}</span>.
        </p>

        <div id="pairing-qr" class="flex justify-center p-4 bg-white rounded-box">
          {Phoenix.HTML.raw(@qr_svg)}
        </div>

        <div class="text-center font-mono text-xs break-all opacity-70">{@pairing_code}</div>

        <button class="btn btn-outline btn-sm w-full" phx-click="regenerate">Regenerate</button>

        <div :if={@tokens != []} class="space-y-2">
          <h2 class="text-sm font-semibold">Paired apps</h2>
          <ul class="space-y-1">
            <li :for={t <- @tokens} class="flex items-center justify-between text-sm">
              <span>Paired {Calendar.strftime(t.inserted_at, "%Y-%m-%d")}</span>
              <button class="btn btn-error btn-xs" phx-click="revoke" phx-value-id={t.id}>
                Revoke
              </button>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
