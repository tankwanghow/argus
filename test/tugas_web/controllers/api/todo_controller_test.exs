defmodule TugasWeb.Api.TodoControllerTest do
  use TugasWeb.ConnCase, async: true

  alias Tugas.Accounts
  alias Tugas.Todos
  import Tugas.EntitiesFixtures

  defp pair(scope) do
    {:ok, {token, _entity}} =
      Accounts.exchange_pairing_code(Accounts.create_pairing_code(scope.user, scope.entity))

    token
  end

  defp post_todo(token, slug, title) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/entities/#{slug}/todos", %{title: title})
  end

  test "creates a todo and returns 201 with the id" do
    scope = entity_scope_fixture()
    token = pair(scope)

    conn = post_todo(token, scope.entity.slug, "Order new gloves")
    assert %{"id" => id} = json_response(conn, 201)
    assert {:ok, todos} = Todos.list_todos(scope)
    assert Enum.any?(todos, &(&1.id == id and &1.title == "Order new gloves"))
  end

  test "401 without a token" do
    scope = entity_scope_fixture()

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/entities/#{scope.entity.slug}/todos", %{title: "x"})

    assert json_response(conn, 401)
  end

  test "403 when the token's entity differs from the path slug" do
    a = entity_scope_fixture()
    b = entity_scope_fixture()
    token = pair(a)

    conn = post_todo(token, b.entity.slug, "x")
    assert json_response(conn, 403)
  end

  test "422 on a blank title" do
    scope = entity_scope_fixture()
    token = pair(scope)

    conn = post_todo(token, scope.entity.slug, "")
    assert json_response(conn, 422)["errors"]
  end
end
