defmodule Tugas.Accounts.UserTokenTest do
  use Tugas.DataCase, async: true

  import Ecto.Query

  alias Tugas.Accounts.UserToken
  import Tugas.EntitiesFixtures

  test "a token row persists an associated entity_id" do
    scope = entity_scope_fixture()

    token =
      Tugas.Repo.insert!(%UserToken{
        token: :crypto.strong_rand_bytes(32),
        context: "api",
        user_id: scope.user.id,
        entity_id: scope.entity.id
      })

    assert Tugas.Repo.get!(UserToken, token.id).entity_id == scope.entity.id
  end
end
