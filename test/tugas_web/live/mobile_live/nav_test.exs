defmodule TugasWeb.MobileLive.NavTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "calendar context shows create shortcuts plus nav tabs", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    slug = manager.entity.slug

    {:ok, view, _html} = live(conn, ~p"/m/#{slug}")

    # ✚ Todo opens the in-place dashboard modal (stays on the page), not a link.
    assert has_element?(view, "button#m-nav-new-todo[phx-click='open_new_todo']")
    refute has_element?(view, "#m-nav-new-todo[href]")
    assert has_element?(view, "#m-nav-todos[href='/m/#{slug}/todos']")
    assert has_element?(view, "#m-nav-new-duty[href='/m/#{slug}/duties/new']")
    assert has_element?(view, "#m-nav-duties[href='/m/#{slug}/duties']")
    refute has_element?(view, "#m-nav-calendar")
    assert has_element?(view, "#m-nav-more")

    # Clicking it opens the create-todo modal on the dashboard.
    view |> element("#m-nav-new-todo") |> render_click()
    assert has_element?(view, "#new-todo-modal")
  end

  test "todos context omits todos tab", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    slug = manager.entity.slug

    {:ok, view, _html} = live(conn, ~p"/m/#{slug}/todos")

    refute has_element?(view, "#m-nav-todos")
    assert has_element?(view, "#m-nav-new-todo[href='/m/#{slug}/todos/new']")
    assert has_element?(view, "#m-nav-duties[href='/m/#{slug}/duties']")
    assert has_element?(view, "#m-nav-calendar[href='/m/#{slug}']")
  end

  test "duties context omits duties tab", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    slug = manager.entity.slug

    {:ok, view, _html} = live(conn, ~p"/m/#{slug}/duties")

    refute has_element?(view, "#m-nav-duties")
    assert has_element?(view, "#m-nav-new-duty[href='/m/#{slug}/duties/new']")
    assert has_element?(view, "#m-nav-todos[href='/m/#{slug}/todos']")
    assert has_element?(view, "#m-nav-calendar[href='/m/#{slug}']")
  end

  test "other context shows navigation tabs without create shortcuts", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    slug = manager.entity.slug

    {:ok, view, _html} = live(conn, ~p"/m/#{slug}/duty-types")

    assert has_element?(view, "#m-nav-todos[href='/m/#{slug}/todos']")
    assert has_element?(view, "#m-nav-duties[href='/m/#{slug}/duties']")
    assert has_element?(view, "#m-nav-calendar[href='/m/#{slug}']")
    refute has_element?(view, "#m-nav-new-todo")
    refute has_element?(view, "#m-nav-new-duty")
    assert has_element?(view, "#m-nav-more")
  end
end
