defmodule ArgusWeb.PageControllerTest do
  use ArgusWeb.ConnCase

  test "GET / shows the marketing page when logged out", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET / redirects a logged-in user to their workspace", %{conn: conn} do
    user = Argus.AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/entities"
  end
end
