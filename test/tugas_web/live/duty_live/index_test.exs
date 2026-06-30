defmodule TugasWeb.DutyLive.IndexTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  alias Tugas.Duties
  alias TugasWeb.DutiesFilter.Store

  setup :register_and_log_in_user

  test "member defaults to the Team scope", %{conn: conn} do
    {scope, _duty} = assigned_member_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(view, "#scope-team.tab-active")
    refute has_element?(view, "#scope-mine.tab-active")
  end

  test "manager defaults to the Team scope", %{conn: conn} do
    {scope, _duty} = manager_duty_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(view, "#scope-team.tab-active")
  end

  test "user menu has all entities and members links", %{conn: conn} do
    {scope, _} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(view, "#user-dropdown")
    assert has_element?(view, "a[href='/entities?pick=1']", "All entities")
    assert has_element?(view, "a[href='/entities/#{scope.entity.slug}/members']", "Members")
    refute has_element?(view, "nav a", "Members")
  end

  test "changing filters persists for the session across remounts", %{conn: conn} do
    {scope, _} = manager_duty_scope_fixture()
    sid = "sid-#{System.unique_integer([:positive])}"
    conn = conn |> log_in_user(scope.user) |> Plug.Conn.put_session(:filter_sid, sid)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    view |> element("#scope-mine") |> render_click()
    view |> form("#duty-status-filter", %{lifecycle: "completed"}) |> render_change()
    view |> element("#duty-search") |> render_keyup(%{"value" => "tax"})

    # The per-browser server store is written by persist/1; reconnecting with the
    # same filter_sid restores it (no client round-trip needed).
    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(view, "#scope-mine.tab-active")
    assert has_element?(view, "#duty-search[value='tax']")

    html = render(view)
    assert html =~ ~s(value="completed" selected)
  end

  test "URL params prefilter the list to Live + Most urgent + empty search, overriding the store",
       %{conn: conn} do
    {scope, _} = manager_duty_scope_fixture()
    sid = "sid-#{System.unique_integer([:positive])}"

    # A different filter is already saved; the URL params must win.
    Store.put(sid, %{
      scope.entity.slug => %{
        "mine" => "true",
        "lifecycle" => "completed",
        "query" => "old search",
        "sort" => "title"
      }
    })

    conn = conn |> log_in_user(scope.user) |> Plug.Conn.put_session(:filter_sid, sid)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties?lifecycle=live&sort=urgency&q=")

    html = render(view)
    assert html =~ ~s(value="live" selected)
    assert html =~ ~s(value="urgency" selected)
    assert has_element?(view, "#duty-search[value='']")
    refute html =~ "old search"

    # The override is persisted, so a remount keeps it.
    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/duties")
    html = render(view)
    assert html =~ ~s(value="live" selected)
    assert html =~ ~s(value="urgency" selected)
  end

  test "URL params prefilter the list to Live + Someday sort", %{conn: conn} do
    {scope, _} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties?lifecycle=live&sort=someday&q=")

    html = render(view)
    assert html =~ ~s(value="live" selected)
    assert html =~ ~s(value="someday" selected)
    assert has_element?(view, "#scope-team.tab-active")
  end

  test "restores duties filters from the store", %{conn: conn} do
    {scope, _} = manager_duty_scope_fixture()
    sid = "sid-#{System.unique_integer([:positive])}"

    Store.put(sid, %{
      scope.entity.slug => %{"mine" => "true", "lifecycle" => "completed", "query" => "tax"}
    })

    conn = conn |> log_in_user(scope.user) |> Plug.Conn.put_session(:filter_sid, sid)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(view, "#scope-mine.tab-active")
    assert has_element?(view, "#duty-search[value='tax']")

    html = render(view)
    assert html =~ ~s(value="completed" selected)
  end

  test "switches scope between Mine and Team", %{conn: conn} do
    {scope, _duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    view |> element("#scope-mine") |> render_click()
    assert has_element?(view, "#scope-mine.tab-active")
    refute has_element?(view, "#scope-team.tab-active")
  end

  test "manager sees the New duty button", %{conn: conn} do
    {scope, _duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(
             view,
             "a[href='/entities/#{scope.entity.slug}/duties/new']",
             "New duty"
           )
  end

  test "overdue duty renders with an overdue badge", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Late filing",
        duty_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2020-01-01],
        open_note: "Late"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties")

    assert has_element?(view, "#duty-row-#{duty.id} [data-urgency=overdue]")
  end

  test "completed filter marks a completed-in-error cycle", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Wrong filing",
        duty_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "open"
      })

    {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

    {:ok, original, _replacement} =
      Duties.mark_completed_in_error(manager, done, %{reason: "oops"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties")

    view |> form("#duty-status-filter", %{lifecycle: "completed"}) |> render_change()
    assert has_element?(view, "#duty-row-#{original.id}", "Completed error")
  end

  test "rows show the latest event status and actor", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    assert {:ok, _} =
             Duties.start_progress(scope, duty, %{note: "Working"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/duties")

    assert has_element?(
             view,
             "#duty-row-#{duty.id}[data-event-count='2'][data-event-status='in_progress']",
             "In progress"
           )

    assert has_element?(view, "#duty-row-#{duty.id}", scope.user.email)
  end

  test "sort dropdown reorders, hides urgency off-live, and infinite scroll appends", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    for i <- 1..30 do
      {:ok, _} =
        Duties.create_duty(manager, %{
          title: "Duty #{String.pad_leading(Integer.to_string(i), 2, "0")}",
          duty_type_id: type.id,
          due_by: Date.add(~D[2026-06-01], i),
          open_note: "n"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties")

    # First page caps at 25.
    assert view |> element("#duties-list") |> render() =~ "Duty 25"
    refute view |> element("#duties-list") |> render() =~ "Duty 26"

    # Infinite scroll reveals the rest.
    render_hook(view, "load_more", %{})
    assert view |> element("#duties-list") |> render() =~ "Duty 26"

    # Urgency option present on live.
    assert has_element?(view, "#duty-sort option[value='urgency']")

    # Switching to Completed hides urgency.
    view |> form("#duty-status-filter", %{lifecycle: "completed"}) |> render_change()
    refute has_element?(view, "#duty-sort option[value='urgency']")
  end

  test "Someday sort floats no-due-date duties to the top", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, _dated} =
      Duties.create_duty(manager, %{
        title: "Has a deadline",
        duty_type_id: type.id,
        due_by: ~D[2026-07-01],
        open_note: "n"
      })

    {:ok, _sd} =
      Duties.create_duty(manager, %{
        title: "Tidy the archive",
        duty_type_id: type.id,
        someday: true,
        open_note: "n"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties")

    # Someday is a sort, not a filter: the Live list shows both dated and dateless duties.
    html = view |> element("#duties-list") |> render()
    assert html =~ "Has a deadline"
    assert html =~ "Tidy the archive"

    # Select the Someday sort → the no-due-date duty floats to the top.
    assert has_element?(view, "#duty-sort option[value='someday']")
    view |> form("#duty-sort-filter", %{sort: "someday"}) |> render_change()
    html = view |> element("#duties-list") |> render()

    {sd_pos, _} = :binary.match(html, "Tidy the archive")
    {dated_pos, _} = :binary.match(html, "Has a deadline")
    assert sd_pos < dated_pos
  end

  test "team (Live) list includes unassigned duties", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Unowned task",
        duty_type_id: type.id,
        primary_assignee_id: nil,
        due_by: ~D[2026-06-20],
        open_note: "Unowned"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties")

    assert has_element?(view, "#duty-row-#{duty.id}", "Unowned task")
    assert has_element?(view, "#duty-row-#{duty.id}", "Unassigned")
  end
end
