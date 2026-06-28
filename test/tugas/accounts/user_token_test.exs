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

  describe "api token builders" do
    test "build_api_token round-trips via verify query, carrying entity_id" do
      scope = entity_scope_fixture()
      {plaintext, struct} = UserToken.build_api_token(scope.user, scope.entity)
      Tugas.Repo.insert!(struct)

      {:ok, query} = UserToken.verify_api_token_query(plaintext)
      {user, token} = Tugas.Repo.one(query)

      assert user.id == scope.user.id
      assert token.entity_id == scope.entity.id
    end

    test "build_api_pairing_token verifies while fresh" do
      scope = entity_scope_fixture()
      {plaintext, struct} = UserToken.build_api_pairing_token(scope.user, scope.entity)
      Tugas.Repo.insert!(struct)

      {:ok, query} = UserToken.verify_api_pairing_token_query(plaintext)
      assert {_user, _token} = Tugas.Repo.one(query)
    end

    test "an api_pairing token older than 5 minutes does not verify" do
      scope = entity_scope_fixture()
      {plaintext, struct} = UserToken.build_api_pairing_token(scope.user, scope.entity)
      inserted = Tugas.Repo.insert!(struct)

      # backdate it 6 minutes
      six_min_ago = DateTime.utc_now(:second) |> DateTime.add(-6, :minute)

      Tugas.Repo.update_all(
        from(t in UserToken, where: t.id == ^inserted.id),
        set: [inserted_at: six_min_ago]
      )

      {:ok, query} = UserToken.verify_api_pairing_token_query(plaintext)
      assert Tugas.Repo.one(query) == nil
    end

    test "verify_api_token_query rejects garbage" do
      assert UserToken.verify_api_token_query("!!not-base64!!") == :error
    end
  end
end
