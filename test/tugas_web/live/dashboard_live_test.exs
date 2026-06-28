defmodule TugasWeb.DashboardLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  alias Tugas.Duties
  alias Tugas.Duties.Urgency
  alias Tugas.Todos
  alias TugasWeb.DashboardLive.CalendarHelpers

  alias Tugas.Holidays.Store

  setup :register_and_log_in_user

  setup do
    Store.clear()
    :ok
  end

  test "renders calendar with nav links", %{conn: conn} do
    scope = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    refute html =~ "Dashboard coming soon"
    assert has_element?(view, "#duty-calendar")
    assert has_element?(view, "#dashboard-todos")
    assert html =~ "📅 Dashboard"
    assert html =~ "💼 Duties"
  end

  test "public holiday appears on its calendar day", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture(%{country_code: "MY"})
    conn = log_in_user(conn, manager.user)
    today = Urgency.today_for(manager.entity.timezone)
    holiday_date = Date.end_of_month(today)

    stub_holidays(fn _country, _year, _region ->
      [%{date: holiday_date, name: "Independence Day", local_name: "Hari Merdeka"}]
    end)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(
             view,
             "#calendar-holiday-#{holiday_date}",
             "Independence Day"
           )

    assert has_element?(
             view,
             "#calendar-day-#{holiday_date} .text-error",
             Integer.to_string(holiday_date.day)
           )
  end

  test "sunday dates render in red on the calendar", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    sunday = ~D[2026-06-07]

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(
             view,
             "#calendar-day-#{sunday} .text-error",
             Integer.to_string(sunday.day)
           )
  end

  test "duty appears on its due date cell", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-18]

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Tax filing",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#calendar-day-#{due} #duty-chip-#{duty.id}", "Tax filing")
  end

  test "calendar duty chips are not links; day modal chips link to show", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-18]

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Desktop link",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    refute has_element?(
             view,
             "#duty-chip-#{duty.id}[href='/entities/#{manager.entity.slug}/duties/#{duty.id}']"
           )

    view |> element("#calendar-day-#{due}") |> render_click()

    assert has_element?(
             view,
             "#day-modal-duty-chip-#{duty.id}[href='/entities/#{manager.entity.slug}/duties/#{duty.id}']"
           )

    duty = Duties.get_duty!(manager, duty.id)
    assert has_element?(view, "#day-modal-duty-chip-#{duty.id}", duty.duty_type.name)
  end

  test "clicking a calendar day with no duties opens empty day modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    empty_day = ~D[2026-06-03]

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    view |> element("#calendar-day-#{empty_day}") |> render_click()

    assert has_element?(view, "#day-modal")
    assert has_element?(view, "#day-modal-empty", "No duties on this day.")
  end

  test "calendar body grid uses equal-height rows for the month", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    today = Urgency.today_for(manager.entity.timezone)
    {year, month} = CalendarHelpers.current_month(today)
    grid = CalendarHelpers.build_month_grid(year, month, today)
    weeks = length(grid.weeks)

    assert has_element?(view, "#calendar-body-grid")
    assert has_element?(view, "#calendar-week-0")
    assert has_element?(view, "#calendar-week-#{weeks - 1}")
    refute html =~ "calendar-week-#{weeks}"
  end

  test "overdue duty chip has error border class", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, reminder_offsets: "7,1")
    today = Urgency.today_for(manager.entity.timezone)
    due = Date.add(today, -3)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Overdue task",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#duty-chip-#{duty.id}.border-error")
  end

  test "someday duty appears in someday strip not calendar day", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "No date task",
        duty_type_id: type.id,
        someday: true,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#someday-strip #duty-chip-#{duty.id}")
  end

  test "mine scope hides other members' unassigned duties", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    member = member_scope_on_entity(manager.entity)
    conn = log_in_user(conn, member.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Team only duty",
        duty_type_id: type.id,
        due_by: ~D[2026-06-20],
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{member.entity.slug}")

    refute has_element?(view, "#duty-chip-#{duty.id}")

    view |> element("#dashboard-scope-mine") |> render_click()
    refute has_element?(view, "#duty-chip-#{duty.id}")

    view |> element("#dashboard-scope-team") |> render_click()
    assert has_element?(view, "#duty-chip-#{duty.id}")
  end

  test "calendar month persists across remounts", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    today = Urgency.today_for(manager.entity.timezone)
    {year, month} = CalendarHelpers.shift_month(today.year, today.month, -1)
    label = CalendarHelpers.month_label(year, month)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    view |> element("#dashboard-prev-month") |> render_click()
    assert has_element?(view, "#dashboard-month-label", label)

    {:ok, _view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/todos")
    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#dashboard-month-label", label)
  end

  test "restores calendar month from the session", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    label = CalendarHelpers.month_label(2026, 5)

    conn =
      conn
      |> log_in_user(manager.user)
      |> init_test_session(%{})
      |> Plug.Conn.put_session(:duties_filters, %{
        manager.entity.slug => %{
          "mine" => "false",
          "lifecycle" => "live",
          "query" => "",
          "sort" => "due_asc",
          "year" => "2026",
          "month" => "5"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#dashboard-month-label", label)
  end

  test "prev month navigation updates duties shown", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    today = Urgency.today_for(manager.entity.timezone)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Last month duty",
        duty_type_id: type.id,
        due_by: Date.add(today, -40),
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")
    refute has_element?(view, "#duty-chip-#{duty.id}")

    view |> element("#dashboard-prev-month") |> render_click()
    assert has_element?(view, "#duty-chip-#{duty.id}")
  end

  test "open todo appears in sidebar and can be completed", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, todo} = Todos.create_todo(manager, %{title: "Buy milk"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#dashboard-todo-#{todo.id}", "Buy milk")

    view |> element("#dashboard-todo-complete-#{todo.id}") |> render_click()
    assert has_element?(view, "#dashboard-todo-#{todo.id}[data-effect=completed]")
    assert has_element?(view, "#dashboard-todo-complete-#{todo.id}[checked]")

    render_click(view, "finish_row_effect", %{"id" => todo.id})
    refute has_element?(view, "#dashboard-todo-#{todo.id}")
    assert has_element?(view, "#dashboard-completed-todo-#{todo.id}", "Buy milk")
  end

  test "completing a todo backfills the open preview from the database", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    # Dashboard open preview shows 11 todos; create one extra to verify backfill.
    for n <- 1..12 do
      {:ok, _} =
        Todos.create_todo(manager, %{title: "Todo #{String.pad_leading("#{n}", 2, "0")}"})
    end

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    open_ids_before = dashboard_open_todo_ids(view)
    assert length(open_ids_before) == 11

    to_complete_id = List.last(open_ids_before)

    view |> element("#dashboard-todo-complete-#{to_complete_id}") |> render_click()
    render_click(view, "finish_row_effect", %{"id" => to_complete_id})

    open_ids_after = dashboard_open_todo_ids(view)
    assert length(open_ids_after) == 11
    refute to_complete_id in open_ids_after
    assert has_element?(view, "#dashboard-completed-todo-#{to_complete_id}")

    assert MapSet.new(open_ids_after)
           |> MapSet.difference(MapSet.new(open_ids_before))
           |> MapSet.size() == 1
  end

  defp stub_holidays(fun) do
    Store.clear()
    Application.put_env(:tugas, :holidays_fetcher, fun)

    on_exit(fn ->
      Application.delete_env(:tugas, :holidays_fetcher)
      Store.clear()
    end)
  end

  defp dashboard_open_todo_ids(view) do
    ~r/id="dashboard-todo-([0-9a-f-]{36})"/
    |> Regex.scan(render(view))
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
  end

  test "completed todo in sidebar can be reopened", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, todo} = Todos.create_todo(manager, %{title: "Restock pantry"})
    {:ok, todo} = Todos.toggle_complete(manager, todo)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#dashboard-completed-todo-#{todo.id}", "Restock pantry")

    view |> element("#dashboard-completed-todo-complete-#{todo.id}") |> render_click()
    assert has_element?(view, "#dashboard-completed-todo-#{todo.id}[data-effect=updated]")

    render_click(view, "finish_row_effect", %{"id" => todo.id})
    refute has_element?(view, "#dashboard-completed-todo-#{todo.id}")
    assert has_element?(view, "#dashboard-todo-#{todo.id}", "Restock pantry")
  end

  test "someday overflow shows +N more and opens modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    for n <- 1..10 do
      {:ok, _duty} =
        Duties.create_duty(manager, %{
          title: "Someday #{String.pad_leading("#{n}", 2, "0")}",
          duty_type_id: type.id,
          someday: true,
          open_note: "open"
        })
    end

    {:ok, hidden} =
      Duties.create_duty(manager, %{
        title: "Someday hidden",
        duty_type_id: type.id,
        someday: true,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#someday-more", "+1 more")
    refute has_element?(view, "#someday-strip #duty-chip-#{hidden.id}")

    view |> element("#someday-more") |> render_click()
    assert has_element?(view, "#someday-modal #someday-modal-duty-chip-#{hidden.id}")

    hidden = Duties.get_duty!(manager, hidden.id)
    assert has_element?(view, "#someday-modal-duty-chip-#{hidden.id}", hidden.duty_type.name)
  end

  test "day overflow opens modal with all duties", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-22]

    for title <- ["One", "Two", "Three", "Four"] do
      {:ok, _duty} =
        Duties.create_duty(manager, %{
          title: title,
          duty_type_id: type.id,
          due_by: due,
          open_note: "open"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#calendar-day-more-#{due}", "+1 more")

    view |> element("#calendar-day-#{due}") |> render_click()
    assert has_element?(view, "#day-modal")
    assert render(view) =~ "Four"
  end
end
