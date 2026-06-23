defmodule ArgusWeb.DashboardFilterControllerTest do
  use ArgusWeb.ConnCase, async: true

  alias ArgusWeb.DashboardFilter.Store

  setup :register_and_log_in_user

  test "persists dashboard filters in the session", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    conn =
      post(conn, ~p"/session/dashboard-filter", %{
        "entity_slug" => scope.entity.slug,
        "mine" => "true",
        "lifecycle" => "completed",
        "query" => "tax"
      })

    assert response(conn, 204)

    assert get_session(conn, :dashboard_filters) == %{
             scope.entity.slug => %{
               "mine" => "true",
               "lifecycle" => "completed",
               "query" => "tax"
             }
           }

    assert Store.get(scope.user.id) == get_session(conn, :dashboard_filters)
  end

  test "merges filters for multiple entities", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    conn =
      conn
      |> post(~p"/session/dashboard-filter", %{
        "entity_slug" => "first-entity",
        "mine" => "true",
        "lifecycle" => "live",
        "query" => "one"
      })
      |> post(~p"/session/dashboard-filter", %{
        "entity_slug" => scope.entity.slug,
        "mine" => "false",
        "lifecycle" => "skipped",
        "query" => "two"
      })

    assert get_session(conn, :dashboard_filters) == %{
             "first-entity" => %{
               "mine" => "true",
               "lifecycle" => "live",
               "query" => "one"
             },
             scope.entity.slug => %{
               "mine" => "false",
               "lifecycle" => "skipped",
               "query" => "two"
             }
           }
  end

  test "rejects requests without an entity slug", %{conn: conn} do
    conn = post(conn, ~p"/session/dashboard-filter", %{"mine" => "true"})
    assert response(conn, 422)
  end

  test "requires authentication" do
    conn = build_conn() |> post(~p"/session/dashboard-filter", %{"entity_slug" => "acme"})
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
