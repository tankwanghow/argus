defmodule TugasWeb.PageControllerTest do
  use TugasWeb.ConnCase

  test "GET / shows the marketing page when logged out", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Recurring duties"
    assert html =~ "always in view"
    assert html =~ "Start tracking free"
    assert html =~ "Built for recurring work"
    assert html =~ ~p"/users/register"
    assert html =~ ~p"/users/log-in"
  end

  test "GET / redirects a logged-in user to their workspace", %{conn: conn} do
    user = Tugas.AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/entities"
  end
end
