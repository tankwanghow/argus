defmodule TugasWeb.DutiesFilterControllerTest do
  use TugasWeb.ConnCase, async: true

  alias TugasWeb.DutiesFilter.Store

  setup :register_and_log_in_user

  test "persists duties filters in the session", %{conn: conn} do
    scope = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    conn =
      post(conn, ~p"/session/duties-filter", %{
        "entity_slug" => scope.entity.slug,
        "mine" => "true",
        "lifecycle" => "completed",
        "query" => "tax"
      })

    assert response(conn, 204)

    assert get_session(conn, :duties_filters) == %{
             scope.entity.slug => %{
               "mine" => "true",
               "lifecycle" => "completed",
               "query" => "tax",
               "sort" => "due_asc"
             }
           }

    assert Store.get(scope.user.id) == get_session(conn, :duties_filters)
  end

  test "merges filters for multiple entities", %{conn: conn} do
    scope = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    conn =
      conn
      |> post(~p"/session/duties-filter", %{
        "entity_slug" => "first-entity",
        "mine" => "true",
        "lifecycle" => "live",
        "query" => "one"
      })
      |> post(~p"/session/duties-filter", %{
        "entity_slug" => scope.entity.slug,
        "mine" => "false",
        "lifecycle" => "skipped",
        "query" => "two"
      })

    assert get_session(conn, :duties_filters) == %{
             "first-entity" => %{
               "mine" => "true",
               "lifecycle" => "live",
               "query" => "one",
               "sort" => "due_asc"
             },
             scope.entity.slug => %{
               "mine" => "false",
               "lifecycle" => "skipped",
               "query" => "two",
               "sort" => "due_asc"
             }
           }
  end

  test "rejects requests without an entity slug", %{conn: conn} do
    conn = post(conn, ~p"/session/duties-filter", %{"mine" => "true"})
    assert response(conn, 422)
  end

  test "requires authentication" do
    conn = build_conn() |> post(~p"/session/duties-filter", %{"entity_slug" => "acme"})
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
