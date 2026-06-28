defmodule TugasWeb.Plugs.ApiTokenAuthTest do
  use TugasWeb.ConnCase, async: true

  alias TugasWeb.Plugs.ApiTokenAuth
  alias Tugas.Accounts
  import Tugas.EntitiesFixtures

  defp call(conn), do: ApiTokenAuth.call(conn, ApiTokenAuth.init([]))

  test "assigns scope + entity id for a valid bearer token" do
    scope = entity_scope_fixture()

    {:ok, {token, _entity}} =
      Accounts.exchange_pairing_code(Accounts.create_pairing_code(scope.user, scope.entity))

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
      |> call()

    refute conn.halted
    assert conn.assigns.current_scope.user.id == scope.user.id
    assert conn.assigns.api_token_entity_id == scope.entity.id
  end

  test "401 + halt when the header is missing" do
    conn = call(build_conn())
    assert conn.halted
    assert conn.status == 401
  end

  test "401 + halt for a bad token" do
    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer garbage")
      |> call()

    assert conn.halted
    assert conn.status == 401
  end
end
