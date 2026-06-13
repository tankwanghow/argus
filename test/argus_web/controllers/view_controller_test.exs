defmodule ArgusWeb.ViewControllerTest do
  use ArgusWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "sets the argus_view cookie and redirects to the local target", %{conn: conn} do
    conn = get(conn, ~p"/set-view?#{[view: "mobile", to: "/m/acme"]}")

    assert redirected_to(conn) == "/m/acme"
    assert conn.resp_cookies["argus_view"].value == "mobile"
  end

  test "rejects a non-local redirect target", %{conn: conn} do
    conn = get(conn, ~p"/set-view?#{[view: "desktop", to: "https://evil.example.com"]}")

    assert redirected_to(conn) == "/entities"
    assert conn.resp_cookies["argus_view"].value == "desktop"
  end
end
