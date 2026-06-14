defmodule ArgusWeb.MobileLive.Obligations do
  use ArgusWeb, :live_view

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  import ArgusWeb.MobileLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:obligations}>
      <div class="sticky top-0 z-30 -mx-4 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200 space-y-2">
        <h1 class="text-lg font-semibold">Obligations</h1>
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
        <div id="m-obligation-status-filters" class="tabs tabs-box tabs-wrap w-full">
          <button
            :for={status <- Index.statuses()}
            id={"m-filter-#{status}"}
            type="button"
            phx-click="filter_status"
            phx-value-status={status}
            class={["tab tab-xs", @status == Index.parse_status(status) && "tab-active"]}
          >
            {Index.status_label(Index.parse_status(status))}
          </button>
        </div>
      </div>

      <ul id="mobile-obligations" class="mt-3 space-y-2">
        <.obligation_card
          :for={row <- @rows}
          row={row}
          today={@today}
          slug={@current_scope.entity.slug}
        />
        <li :if={@rows == []} id="m-obligations-empty" class="text-center text-base-content/60 py-12">
          {Index.empty_message(@status)}
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
     |> assign(:status, Index.default_status(scope))
     |> assign(:query, "")
     |> load_rows()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status, Index.parse_status(status)) |> load_rows()}
  end

  def handle_event("search", params, socket) do
    query = Map.get(params, "value") || Map.get(params, "q") || ""
    {:noreply, socket |> assign(:query, query) |> load_rows()}
  end

  defp load_rows(socket) do
    %{current_scope: scope, today: today, status: status, query: query} = socket.assigns
    assign(socket, :rows, Index.load_rows(scope, today, status, query))
  end
end
