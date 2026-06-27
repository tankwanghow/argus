defmodule TugasWeb.DashboardLive.Index do
  use TugasWeb, :live_view

  alias Tugas.Duties.Urgency
  alias Tugas.Todos
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DutiesFilter

  @todo_preview_limit 22

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} container_class="max-w-7xl">
      <div id="dashboard" class="tugas-page space-y-4">
        <div class="flex flex-col lg:flex-row gap-6">
          <div class="flex-1 min-w-0 space-y-3">
            <div class="flex flex-wrap items-center gap-2">
              <div id="dashboard-scope-toggle" class="tabs tabs-box">
                <button
                  id="dashboard-scope-mine"
                  type="button"
                  phx-click="set_scope"
                  phx-value-mine="true"
                  class={["tab", @mine? && "tab-active font-bold"]}
                >
                  Mine
                </button>
                <button
                  id="dashboard-scope-team"
                  type="button"
                  phx-click="set_scope"
                  phx-value-mine="false"
                  class={["tab", !@mine? && "tab-active font-bold"]}
                >
                  Team
                </button>
              </div>

              <div class="flex items-center gap-1 ml-auto">
                <button
                  id="dashboard-prev-month"
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="prev_month"
                >
                  ‹
                </button>
                <span id="dashboard-month-label" class="text-sm font-semibold min-w-32 text-center">
                  {Calendar.month_label(@year, @month)}
                </span>
                <button
                  id="dashboard-next-month"
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="next_month"
                >
                  ›
                </button>
                <button
                  id="dashboard-today"
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="today"
                >
                  Today
                </button>
              </div>
            </div>

            <.duty_calendar
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
              someday_modal_open?={@someday_modal_open?}
            />
          </div>

          <div class="w-[15%] border-1 rounded p-2">
            <.dashboard_todos_panel
              todos={@todos}
              slug={@current_scope.entity.slug}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    {year, month} = Calendar.current_month(today)

    socket =
      socket
      |> assign(:today, today)
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:day_modal_date, nil)
      |> assign(:day_modal_rows, [])
      |> assign(:someday_modal_open?, false)
      |> DutiesFilter.assign_filters(session)
      |> load_dashboard()

    {:ok, socket}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket
     |> assign(:mine?, mine == "true")
     |> load_dashboard()
     |> DutiesFilter.persist()}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, -1)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, 1)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("today", _params, socket) do
    today = socket.assigns.today
    {year, month} = Calendar.current_month(today)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("open_day_modal", %{"date" => iso}, socket) do
    date = Date.from_iso8601!(iso)
    rows = Map.get(socket.assigns.grouped, date, [])

    {:noreply,
     socket
     |> assign(day_modal_date: date, day_modal_rows: rows)
     |> assign(:someday_modal_open?, false)}
  end

  def handle_event("close_day_modal", _params, socket) do
    {:noreply, assign(socket, day_modal_date: nil, day_modal_rows: [])}
  end

  def handle_event("open_someday_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:someday_modal_open?, true)
     |> assign(day_modal_date: nil, day_modal_rows: [])}
  end

  def handle_event("close_someday_modal", _params, socket) do
    {:noreply, assign(socket, :someday_modal_open?, false)}
  end

  def handle_event("toggle_todo_complete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    result =
      with {:ok, todo} <- Todos.get_todo(scope, id),
           :ok <- complete_or_reopen(scope, todo) do
        :ok
      else
        _ -> :error
      end

    socket =
      case result do
        :ok -> load_todos(socket)
        :error -> socket
      end

    {:noreply, socket}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    cond do
      socket.assigns.day_modal_date ->
        {:noreply, assign(socket, day_modal_date: nil, day_modal_rows: [])}

      socket.assigns.someday_modal_open? ->
        {:noreply, assign(socket, :someday_modal_open?, false)}

      true ->
        {:noreply, socket}
    end
  end

  defp load_dashboard(socket) do
    %{current_scope: scope, today: today, mine?: mine?, year: year, month: month} =
      socket.assigns

    month_rows = Calendar.load_month_rows(scope, today, mine?, year, month)
    someday_rows = Calendar.load_someday_rows(scope, today, mine?)
    grid = Calendar.build_month_grid(year, month, today)
    grouped = Calendar.group_by_date(month_rows)

    socket
    |> assign(grid: grid, grouped: grouped, someday_rows: someday_rows)
    |> load_todos()
  end

  defp load_todos(socket) do
    scope = socket.assigns.current_scope

    todos =
      case Todos.list_todos_page(scope, status: :open, limit: @todo_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    assign(socket, :todos, todos)
  end

  defp complete_or_reopen(scope, todo) do
    case Todos.toggle_complete(scope, todo) do
      {:ok, _} -> :ok
      :not_authorise -> :error
      :not_found -> :error
    end
  end
end
