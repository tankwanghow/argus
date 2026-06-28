defmodule TugasWeb.Api.PairControllerTest do
  use TugasWeb.ConnCase, async: true

  alias Tugas.Accounts
  import Tugas.EntitiesFixtures

  test "exchanges a valid pairing code for a token" do
    scope = entity_scope_fixture()
    code = Accounts.create_pairing_code(scope.user, scope.entity)

    conn = post(build_conn(), "/api/pair", %{pairing_code: code})
    body = json_response(conn, 201)

    assert is_binary(body["token"])
    assert body["entity_slug"] == scope.entity.slug
    assert {_user, entity_id} = Accounts.fetch_api_token_user(body["token"])
    assert entity_id == scope.entity.id
  end

  test "401 for an unknown code" do
    conn = post(build_conn(), "/api/pair", %{pairing_code: "nope"})
    assert json_response(conn, 401)
  end

  test "401 when reusing a code (single-use)" do
    scope = entity_scope_fixture()
    code = Accounts.create_pairing_code(scope.user, scope.entity)

    assert json_response(post(build_conn(), "/api/pair", %{pairing_code: code}), 201)
    assert json_response(post(build_conn(), "/api/pair", %{pairing_code: code}), 401)
  end
end
