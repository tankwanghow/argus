defmodule ArgusWeb.ViewModeControllerTest do
  use ArgusWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "sets the argus_view cookie and redirects to the local target via mode param", %{
    conn: conn
  } do
    conn = get(conn, ~p"/view-mode?#{[mode: "mobile", to: "/m/acme"]}")

    assert redirected_to(conn) == "/m/acme"
    assert conn.resp_cookies["argus_view"].value == "mobile"
  end

  test "legacy set-view route accepts view param", %{conn: conn} do
    conn = get(conn, ~p"/set-view?#{[view: "desktop", to: "/entities/acme"]}")

    assert redirected_to(conn) == "/entities/acme"
    assert conn.resp_cookies["argus_view"].value == "desktop"
  end

  test "rejects a non-local redirect target", %{conn: conn} do
    conn = get(conn, ~p"/view-mode?#{[mode: "desktop", to: "https://evil.example.com"]}")

    assert redirected_to(conn) == "/entities"
    assert conn.resp_cookies["argus_view"].value == "desktop"
  end
end
