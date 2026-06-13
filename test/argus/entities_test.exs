defmodule Argus.EntitiesTest do
  use Argus.DataCase, async: true

  alias Argus.Accounts.Scope
  alias Argus.Entities
  alias Argus.Entities.Membership

  import Argus.AccountsFixtures

  describe "create_entity/2" do
    test "creates entity and admin membership" do
      scope = Scope.for_user(user_fixture())

      assert {:ok, entity} = Entities.create_entity(scope, %{slug: "acme", name: "Acme Sdn Bhd"})
      assert entity.slug == "acme"

      membership = Entities.get_membership!(scope.user, entity)
      assert membership.role == "admin"
      assert membership.is_default
    end
  end

  describe "list_user_entities/1" do
    test "excludes soft-deleted entities" do
      scope = Scope.for_user(user_fixture())
      {:ok, entity} = Entities.create_entity(scope, %{slug: "acme", name: "Acme"})

      entity
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Argus.Repo.update!()

      assert Entities.list_user_entities(scope.user) == []
    end
  end

  describe "get_entity_by_slug_for_user!/2" do
    test "raises when entity is soft-deleted" do
      scope = Scope.for_user(user_fixture())
      {:ok, entity} = Entities.create_entity(scope, %{slug: "acme", name: "Acme"})

      entity
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Argus.Repo.update!()

      assert_raise Ecto.NoResultsError, fn ->
        Entities.get_entity_by_slug_for_user!("acme", scope.user)
      end
    end
  end

  describe "seats_available?/1 and invitations" do
    test "invite rejects when seats are full" do
      scope = Scope.for_user(user_fixture())
      {:ok, entity} = Entities.create_entity(scope, %{slug: "tiny", name: "Tiny", seat_limit: 1})
      membership = Entities.get_membership!(scope.user, entity)
      scope = Scope.put_entity(scope, entity, membership)

      assert {:error, :seat_limit_reached} =
               Entities.invite_member(scope, "other@example.com", "member")
    end

    test "accept re-checks seat limit at accept time" do
      admin_scope = Scope.for_user(user_fixture())

      {:ok, entity} =
        Entities.create_entity(admin_scope, %{slug: "full", name: "Full", seat_limit: 2})

      membership = Entities.get_membership!(admin_scope.user, entity)
      admin_scope = Scope.put_entity(admin_scope, entity, membership)

      {:ok, invitation} = Entities.invite_member(admin_scope, "member@example.com", "member")
      {:ok, late_invitation} = Entities.invite_member(admin_scope, "late@example.com", "member")

      member = user_fixture(%{email: "member@example.com"})
      assert {:ok, %Membership{}} = Entities.accept_invitation(member, invitation.token)

      late_user = user_fixture(%{email: "late@example.com"})

      assert {:error, :seat_limit_reached} =
               Entities.accept_invitation(late_user, late_invitation.token)
    end
  end
end
