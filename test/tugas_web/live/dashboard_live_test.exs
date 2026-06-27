defmodule TugasWeb.DashboardLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  alias Tugas.Duties
  alias Tugas.Duties.Urgency
  alias Tugas.Todos

  setup :register_and_log_in_user

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

    view |> element("#calendar-day-more-#{due}") |> render_click()
    assert has_element?(view, "#day-modal")
    assert render(view) =~ "Four"
  end
end
