defmodule ArgusWeb.LocaleControllerTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.EntitiesFixtures

  setup %{conn: conn} do
    scope = entity_scope_fixture()
    %{conn: log_in_user(conn, scope.user), scope: scope}
  end

  test "updates the user's locale and redirects to the referring path", %{
    conn: conn,
    scope: scope
  } do
    slug = scope.entity.slug

    conn =
      conn
      |> put_req_header("referer", "http://localhost:4000/entities/#{slug}?x=1")
      |> get(~p"/locale/ms")

    assert redirected_to(conn) == "/entities/#{slug}?x=1"
    assert Argus.Repo.reload(scope.user).locale == "ms"
  end

  test "ignores an unsupported locale", %{conn: conn, scope: scope} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost:4000/entities/#{scope.entity.slug}")
      |> get(~p"/locale/xx")

    assert redirected_to(conn) == "/entities/#{scope.entity.slug}"
    assert Argus.Repo.reload(scope.user).locale == "en"
  end

  test "falls back to / for an external referer", %{conn: conn} do
    conn =
      conn |> put_req_header("referer", "https://evil.example.com/") |> get(~p"/locale/ms")

    assert redirected_to(conn) == "/"
  end

  test "an anonymous visitor sets the argus_locale cookie", %{} do
    conn =
      build_conn()
      |> put_req_header("referer", "http://localhost:4000/")
      |> get(~p"/locale/zh")

    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["argus_locale"].value == "zh"
  end
end
