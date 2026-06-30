defmodule TugasWeb.DashboardLive.IndexHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Tugas.Duties.Urgency
  alias Tugas.Todos
  alias Tugas.Todos.Todo
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DutiesFilter

  @open_preview_limit 11
  @completed_preview_limit 5

  def open_preview_limit, do: @open_preview_limit
  def completed_preview_limit, do: @completed_preview_limit

  def mount_dashboard(socket, session) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    filters = DutiesFilter.load(session, scope)

    socket =
      socket
      |> assign(:today, today)
      |> assign(:day_modal_date, nil)
      |> assign(:day_modal_rows, [])
      |> assign(:day_modal_holidays, [])
      |> assign(:someday_modal_open?, false)
      |> assign(:row_effects, %{})
      |> DutiesFilter.assign_sid(session)
      |> DutiesFilter.assign_from_filters(filters)
      |> assign_calendar_month(filters, today)
      |> load_dashboard()

    {:ok, socket}
  end

  defp assign_calendar_month(socket, filters, today) do
    {default_year, default_month} = Calendar.current_month(today)

    {year, month} =
      case {filters.year, filters.month} do
        {y, m} when is_integer(y) and is_integer(m) -> {y, m}
        _ -> {default_year, default_month}
      end

    assign(socket, year: year, month: month)
  end

  def handle_set_scope(socket, mine) do
    socket
    |> assign(:mine?, mine == "true")
    |> load_dashboard()
    |> DutiesFilter.persist()
  end

  def handle_prev_month(socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, -1)

    socket
    |> assign(year: year, month: month)
    |> load_dashboard()
    |> DutiesFilter.persist()
  end

  def handle_next_month(socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, 1)

    socket
    |> assign(year: year, month: month)
    |> load_dashboard()
    |> DutiesFilter.persist()
  end

  def handle_today(socket) do
    today = socket.assigns.today
    {year, month} = Calendar.current_month(today)

    socket
    |> assign(year: year, month: month)
    |> load_dashboard()
    |> DutiesFilter.persist()
  end

  def handle_open_day_modal(socket, iso) do
    date = Date.from_iso8601!(iso)
    rows = Map.get(socket.assigns.grouped, date, [])
    holidays = Map.get(socket.assigns.holidays_by_date, date, [])

    socket
    |> assign(day_modal_date: date, day_modal_rows: rows, day_modal_holidays: holidays)
    |> assign(:someday_modal_open?, false)
  end

  def handle_close_day_modal(socket) do
    assign(socket, day_modal_date: nil, day_modal_rows: [], day_modal_holidays: [])
  end

  def handle_open_someday_modal(socket) do
    socket
    |> assign(:someday_modal_open?, true)
    |> assign(day_modal_date: nil, day_modal_rows: [])
  end

  def handle_close_someday_modal(socket) do
    assign(socket, :someday_modal_open?, false)
  end

  def handle_toggle_todo_complete(socket, id) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        case Todos.toggle_complete(scope, todo) do
          {:ok, updated} ->
            effect = if Todo.completed?(updated), do: :completed, else: :updated

            socket =
              if Todo.completed?(updated) do
                assign(socket, :todos, replace_todo(socket.assigns.todos, updated))
              else
                assign(
                  socket,
                  :completed_todos,
                  replace_todo(socket.assigns.completed_todos, updated)
                )
              end

            put_row_effect(socket, updated.id, effect)

          _ ->
            socket
        end

      _ ->
        socket
    end
  end

  def handle_finish_row_effect(socket, id) do
    row_effects = Map.delete(socket.assigns.row_effects || %{}, id)

    socket
    |> assign(:row_effects, row_effects)
    |> load_todos()
  end

  def handle_close_modal_on_escape(socket) do
    cond do
      socket.assigns.day_modal_date ->
        handle_close_day_modal(socket)

      socket.assigns.someday_modal_open? ->
        handle_close_someday_modal(socket)

      true ->
        socket
    end
  end

  defp load_dashboard(socket) do
    %{current_scope: scope, today: today, mine?: mine?, year: year, month: month} =
      socket.assigns

    month_rows = Calendar.load_month_rows(scope, today, mine?, year, month)
    someday_rows = Calendar.load_someday_rows(scope, today, mine?)
    urgent_rows = Calendar.load_urgent_rows(scope, today, mine?)
    holidays_by_date = Calendar.load_holidays_by_date(scope, year, month)

    grid =
      Calendar.build_month_grid(year, month, today)
      |> Calendar.annotate_holidays(holidays_by_date)

    grouped = Calendar.group_by_date(month_rows)

    socket
    |> assign(
      grid: grid,
      grouped: grouped,
      someday_rows: someday_rows,
      urgent_rows: urgent_rows,
      holidays_by_date: holidays_by_date
    )
    |> load_todos()
  end

  defp load_todos(socket) do
    scope = socket.assigns.current_scope

    todos =
      case Todos.list_todos_page(scope, status: :open, limit: @open_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    completed_todos =
      case Todos.list_todos_page(scope, status: :completed, limit: @completed_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    socket
    |> assign(:todos, todos)
    |> assign(:completed_todos, completed_todos)
  end

  defp replace_todo(todos, %Todo{} = updated) do
    case Enum.find_index(todos, &(&1.id == updated.id)) do
      nil -> todos
      idx -> List.replace_at(todos, idx, updated)
    end
  end

  defp put_row_effect(socket, todo_id, effect) do
    assign(socket, :row_effects, Map.put(socket.assigns.row_effects || %{}, todo_id, effect))
  end
end
