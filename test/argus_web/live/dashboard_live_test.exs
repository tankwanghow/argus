defmodule ArgusWeb.DashboardLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  setup :register_and_log_in_user

  test "member defaults to My work tab", %{conn: conn} do
    {scope, _obligation} = assigned_member_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#tab-my-work.tab-active")
    refute has_element?(view, "#tab-team-overview.tab-active")
  end

  test "manager defaults to Team overview tab", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#tab-team-overview.tab-active")
  end

  test "switches tabs", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    view |> element("#tab-my-work") |> render_click()
    assert has_element?(view, "#tab-my-work.tab-active")
  end
end