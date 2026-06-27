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

    view |> element("#dashboard-todo-#{todo.id} input[type=checkbox]") |> render_click()

    refute has_element?(view, "#dashboard-todo-#{todo.id}")
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