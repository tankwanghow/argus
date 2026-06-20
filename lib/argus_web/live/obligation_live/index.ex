defmodule ArgusWeb.ObligationLive.Index do
  use ArgusWeb, :live_view

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligations-index" class="space-y-3">
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

        <div class="argus-page-toolbar flex flex-col gap-2 sm:flex-row sm:items-center">
          <div id="obligation-status-filters" class="tabs tabs-box tabs-wrap flex-1 min-w-0">
            <.link
              :for={status <- Index.statuses()}
              id={"filter-#{status}"}
              phx-click="filter_status"
              phx-value-status={status}
              class={["tab", @status == Index.parse_status(status) && "tab-active font-bold text-xl"]}
            >
              {Index.status_label(Index.parse_status(status))}
            </.link>
          </div>
          <input
            id="obligation-search"
            type="search"
            name="q"
            placeholder="Search…"
            phx-keyup="search"
            phx-debounce="150"
            value={@query}
            class="input input-sm w-full sm:w-48 shrink-0"
          />
        </div>

        <section class="argus-section">
          <ul id="obligations-list" class="argus-row-list">
            <li :for={row <- @rows} id={"obligation-#{row.obligation.id}"}>
              <.link
                navigate={
                  ~p"/entities/#{@current_scope.entity.slug}/obligations/#{row.obligation.id}"
                }
                class={[
                  "argus-compact-row block border-l-4",
                  if(row.cycle_status == :live, do: tier_border(row.tier), else: "border-transparent")
                ]}
              >
                <div class="grid grid-cols-1 sm:grid-cols-[minmax(0,1fr)_9rem_7rem] gap-x-4 gap-y-1 items-center">
                  <div class="flex flex-wrap items-center gap-x-2 gap-y-1 min-w-0">
                    <span class="font-medium">{row.obligation.title}</span>
                    <.obligation_status_badge
                      :if={row.cycle_status != :live}
                      cycle_status={row.cycle_status}
                      in_error={!is_nil(row.obligation.completed_in_error_at)}
                    />
                    <.urgency_badge
                      :if={row.cycle_status == :live}
                      tier={row.tier}
                      due_by={row.obligation.due_by}
                      today={@today}
                    />
                  </div>
                  <div class="text-sm text-base-content/60 truncate sm:text-right">
                    {row.obligation.obligation_type.name}
                  </div>
                  <div class="text-sm text-base-content/60 sm:text-right">
                    <div>{format_date(row.obligation.due_by)}</div>
                    <div :if={row.cycle_status == :live} class="text-xs">
                      {due_label(row.obligation.due_by, @today)}
                    </div>
                    <div :if={row.cycle_status == :completed} class="text-xs">
                      Completed {format_datetime(row.obligation.completed_at)}
                    </div>
                    <div :if={row.cycle_status == :cancelled} class="text-xs">Cancelled</div>
                  </div>
                </div>
              </.link>
            </li>
            <li :if={@rows == []} id="obligations-empty" class="py-8 text-center text-base-content/60">
              {Index.empty_message(@status)}
            </li>
          </ul>
        </section>
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
