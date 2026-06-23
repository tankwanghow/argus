defmodule ArgusWeb.DashboardLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Obligations

  setup :register_and_log_in_user

  test "member defaults to the Mine scope", %{conn: conn} do
    {scope, _obligation} = assigned_member_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#scope-mine.tab-active")
    refute has_element?(view, "#scope-team.tab-active")
  end

  test "manager defaults to the Team scope", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#scope-team.tab-active")
  end

  test "user menu has all entities and members links", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#user-dropdown")
    assert has_element?(view, "a[href='/entities?pick=1']", "All entities")
    assert has_element?(view, "a[href='/entities/#{scope.entity.slug}/members']", "Members")
    refute has_element?(view, "nav a", "Members")
  end

  test "changing filters persists for the session across remounts", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    view |> element("#scope-mine") |> render_click()
    view |> form("#obligation-status-filter", %{lifecycle: "completed"}) |> render_change()
    view |> element("#obligation-search") |> render_keyup(%{"value" => "tax"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#scope-mine.tab-active")
    assert has_element?(view, "#obligation-search[value='tax']")

    html = render(view)
    assert html =~ ~s(value="completed" selected)
  end

  test "restores dashboard filters from the session", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()

    conn =
      conn
      |> log_in_user(scope.user)
      |> init_test_session(%{})
      |> Plug.Conn.put_session(:dashboard_filters, %{
        scope.entity.slug => %{
          "mine" => "true",
          "lifecycle" => "completed",
          "query" => "tax"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#scope-mine.tab-active")
    assert has_element?(view, "#obligation-search[value='tax']")

    html = render(view)
    assert html =~ ~s(value="completed" selected)
  end

  test "switches scope between Mine and Team", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    view |> element("#scope-mine") |> render_click()
    assert has_element?(view, "#scope-mine.tab-active")
    refute has_element?(view, "#scope-team.tab-active")
  end

  test "manager sees the New duty button", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(
             view,
             "a[href='/entities/#{scope.entity.slug}/obligations/new']",
             "New duty"
           )
  end

  test "overdue obligation renders with an overdue badge", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "Late filing",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2020-01-01],
        open_note: "Late"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#obligation-row-#{obligation.id} [data-urgency=overdue]")
  end

  test "completed filter marks a completed-in-error cycle", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "Wrong filing",
        obligation_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "open"
      })

    {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

    {:ok, original, _replacement} =
      Obligations.mark_completed_in_error(manager, done, %{reason: "oops"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    view |> form("#obligation-status-filter", %{lifecycle: "completed"}) |> render_change()
    assert has_element?(view, "#obligation-row-#{original.id}", "in error")
  end

  test "rows show the latest event status and actor", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    assert {:ok, _} =
             Obligations.start_progress(scope, obligation, %{note: "Working"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(
             view,
             "#obligation-row-#{obligation.id}[data-event-count='2'][data-event-status='in_progress']",
             "In progress"
           )

    assert has_element?(view, "#obligation-row-#{obligation.id}", scope.user.email)
  end

  test "team (Live) list includes unassigned obligations", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "Unowned task",
        obligation_type_id: type.id,
        primary_assignee_id: nil,
        due_by: ~D[2026-06-20],
        open_note: "Unowned"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#obligation-row-#{obligation.id}", "Unowned task")
    assert has_element?(view, "#obligation-row-#{obligation.id}", "Unassigned")
  end
end
