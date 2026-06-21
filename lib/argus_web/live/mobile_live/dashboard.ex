defmodule ArgusWeb.MobileLive.Dashboard do
  use ArgusWeb, :live_view

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  import ArgusWeb.MobileLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>
      <div class="sticky top-0 z-30 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200 space-y-2">
        <h1 class="text-lg font-semibold truncate">{@current_scope.entity.name}</h1>
        <input
          id="m-obligation-search"
          type="search"
          name="q"
          placeholder="Search title, type, assignee…"
          phx-keyup="search"
          phx-debounce="150"
          value={@query}
          class="input w-full"
        />
        <div class="flex items-center gap-2">
          <div id="m-obligation-scope-toggle" class="tabs tabs-box flex-1">
            <button
              id="m-scope-mine"
              type="button"
              phx-click="set_scope"
              phx-value-mine="true"
              class={["tab flex-1", @mine? && "tab-active"]}
            >
              Mine
            </button>
            <button
              id="m-scope-team"
              type="button"
              phx-click="set_scope"
              phx-value-mine="false"
              class={["tab flex-1", !@mine? && "tab-active"]}
            >
              Team
            </button>
          </div>
          <form id="m-obligation-status-filter" phx-change="set_status">
            <select name="lifecycle" class="select select-sm">
              <option
                :for={{value, label} <- Index.lifecycles()}
                value={value}
                selected={@lifecycle == Index.parse_lifecycle(value)}
              >
                {label}
              </option>
            </select>
          </form>
        </div>
      </div>

      <ul id="mobile-obligations" class="px-4 space-y-2">
        <.obligation_card
          :for={row <- @rows}
          row={row}
          today={@today}
          slug={@current_scope.entity.slug}
        />
        <li
          :if={@rows == []}
          id="m-obligations-empty"
          class="text-center text-base-content/60 py-12"
        >
          {Index.empty_message(@mine?, @lifecycle)}
        </li>
      </ul>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Argus.Obligations.Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> assign(:mine?, Index.default_mine?(scope))
     |> assign(:lifecycle, :live)
     |> assign(:query, "")
     |> load_rows()}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply, socket |> assign(:mine?, mine == "true") |> load_rows()}
  end

  def handle_event("set_status", %{"lifecycle" => lifecycle}, socket) do
    {:noreply, socket |> assign(:lifecycle, Index.parse_lifecycle(lifecycle)) |> load_rows()}
  end

  def handle_event("search", params, socket) do
    query = Map.get(params, "value") || Map.get(params, "q") || ""
    {:noreply, socket |> assign(:query, query) |> load_rows()}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_rows(socket) do
    %{current_scope: scope, today: today, mine?: mine?, lifecycle: lifecycle, query: query} =
      socket.assigns

    assign(socket, :rows, Index.load_rows(scope, today, mine?, lifecycle, query))
  end
end
