defmodule TugasWeb.DashboardLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the placeholder dashboard", %{conn: conn} do
    scope = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    assert html =~ "Dashboard coming soon"
    assert html =~ scope.entity.name
    assert has_element?(view, "#dashboard")
  end
end
