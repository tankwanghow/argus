defmodule ArgusWeb.ObligationLive.Index do
  use ArgusWeb, :live_view

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligations-index">
        <.header>
          Obligations
          <:actions>
            <.link
              :if={Argus.Authorization.can?(@current_scope, :create_obligation)}
              navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/new"}
              class="btn btn-primary btn-sm"
            >
              New obligation
            </.link>
          </:actions>
        </.header>

        <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div id="obligation-status-filters" class="tabs tabs-box w-full sm:w-fit">
            <button
              :for={status <- Index.statuses()}
              id={"filter-#{status}"}
              type="button"
              phx-click="filter_status"
              phx-value-status={status}
              class={["tab", @status == Index.parse_status(status) && "tab-active"]}
            >
              {Index.status_label(Index.parse_status(status))}
            </button>
          </div>
          <input
            id="obligation-search"
            type="search"
            name="q"
            placeholder="Search title, type, assignee…"
            phx-keyup="search"
            phx-debounce="150"
            value={@query}
            class="input input-sm w-full sm:max-w-xs"
          />
        </div>

        <ul id="obligations-list" class="mt-6 divide-y divide-base-300">
          <li :for={row <- @rows} id={"obligation-#{row.obligation.id}"} class="py-3">
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/#{row.obligation.id}"}
              class="flex items-center justify-between gap-3 hover:opacity-80"
            >
              <div class="min-w-0">
                <div class="font-medium truncate">{row.obligation.title}</div>
                <div class="text-sm text-base-content/60 truncate">
                  {row.obligation.obligation_type.name} · {list_meta(row, @today)}
                </div>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <.obligation_status_badge
                  :if={row.cycle_status != :live}
                  cycle_status={row.cycle_status}
                />
                <.urgency_badge :if={row.cycle_status == :live} urgency={row.urgency} />
              </div>
            </.link>
          </li>
          <li :if={@rows == []} id="obligations-empty" class="py-8 text-center text-base-content/60">
            {Index.empty_message(@status)}
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Argus.Obligations.Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> assign(:status, :live)
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

  defp list_meta(%{cycle_status: :completed, obligation: o}, _today) do
    "completed #{format_datetime(o.completed_at)} · due #{format_date(o.due_by)}"
  end

  defp list_meta(%{cycle_status: :cancelled, obligation: o}, _today) do
    "cancelled · due #{format_date(o.due_by)}"
  end

  defp list_meta(%{obligation: o}, today) do
    "due #{format_date(o.due_by)} · #{due_label(o.due_by, today)}"
  end
end
