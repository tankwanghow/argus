defmodule Argus.EntitiesTest do
  use Argus.DataCase, async: true

  alias Argus.Accounts.Scope
  alias Argus.Entities
  alias Argus.Entities.Membership
  alias Argus.Obligations
  alias Argus.Obligations.SampleTypes

  import Argus.AccountsFixtures

  describe "create_entity/2" do
    test "creates entity and admin membership" do
      scope = Scope.for_user(user_fixture())

      assert {:ok, entity} = Entities.create_entity(scope, %{slug: "acme", name: "Acme Sdn Bhd"})
      assert entity.slug == "acme"

      membership = Entities.get_membership!(scope.user, entity)
      assert membership.role == "admin"
      assert membership.is_default

      scope = Scope.put_entity(scope, entity, membership)
      types = Obligations.list_types(scope)
      assert length(types) == length(SampleTypes.samples())
      assert Enum.any?(types, &(&1.name == "EPF Monthly"))
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

  describe "revoke_invitation/2" do
    test "admin deletes a pending invitation" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "pending@example.com", "member")

      assert {:ok, _} = Entities.revoke_invitation(admin_scope, invitation.id)
      assert Entities.list_pending_invitations(admin_scope.entity) == []
    end

    test "revoking frees the email for a new invite" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "pending@example.com", "member")

      assert {:ok, _} = Entities.revoke_invitation(admin_scope, invitation.id)

      assert {:ok, _} =
               Entities.invite_member(admin_scope, "pending@example.com", "manager")
    end

    test "manager cannot revoke invitations" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()
      manager_user = user_fixture()

      %Membership{
        user_id: manager_user.id,
        entity_id: admin_scope.entity.id,
        role: "manager",
        accepted_at: DateTime.utc_now(:second)
      }
      |> Membership.changeset(%{})
      |> Argus.Repo.insert!()

      manager_membership = Entities.get_membership!(manager_user, admin_scope.entity)

      manager_scope =
        Scope.put_entity(Scope.for_user(manager_user), admin_scope.entity, manager_membership)

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "pending@example.com", "member")

      assert :not_authorise = Entities.revoke_invitation(manager_scope, invitation.id)
    end

    test "returns not_found for accepted invitations" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "member@example.com", "member")

      member = user_fixture(%{email: "member@example.com"})
      assert {:ok, _} = Entities.accept_invitation(member, invitation.token)

      assert {:error, :not_found} =
               Entities.revoke_invitation(admin_scope, invitation.id)
    end
  end

  describe "invite_member/4 email delivery" do
    import Swoosh.TestAssertions

    alias Argus.Entities.Invitation

    # Building fixtures sends login emails into this process's mailbox; drain
    # them so the assertions below target only the invite email.
    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    test "delivers an invite email containing the accept URL built from the encoded token" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()
      flush_emails()

      url_fun = fn encoded -> "https://argus.test/invitations/#{encoded}" end

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "invitee@example.com", "member", url_fun)

      expected_url = "https://argus.test/invitations/#{Invitation.encode_token(invitation.token)}"

      assert_email_sent(fn email ->
        assert {_, "invitee@example.com"} = hd(email.to)
        assert email.text_body =~ expected_url
        assert email.text_body =~ admin_scope.entity.name
      end)
    end

    test "without a url_fun (3-arity) it creates the invitation and sends no email" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()
      flush_emails()

      assert {:ok, _invitation} =
               Entities.invite_member(admin_scope, "invitee@example.com", "member")

      assert_no_email_sent()
    end
  end

  describe "invite_member/4 without an email (QR invite)" do
    test "creates a pending invitation with no email and sends nothing" do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()

      assert {:ok, invitation} =
               Entities.invite_member(scope, nil, "member", fn _enc -> "http://x/" end)

      assert is_nil(invitation.email)
      assert invitation.role == "member"
    end

    test "treats a blank email as no email" do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      assert {:ok, invitation} = Entities.invite_member(scope, "", "member")
      assert is_nil(invitation.email)
    end
  end

  describe "get_invitation_by_encoded_token/1" do
    alias Argus.Entities.Invitation

    test "returns the pending invitation (entity preloaded) for a valid encoded token" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "invitee@example.com", "member")

      encoded = Invitation.encode_token(invitation.token)

      assert {:ok, fetched} = Entities.get_invitation_by_encoded_token(encoded)
      assert fetched.id == invitation.id
      assert fetched.entity.id == admin_scope.entity.id
    end

    test "returns :error for a garbage token" do
      assert :error = Entities.get_invitation_by_encoded_token("garbage!!!")
    end

    test "returns :error for an already-accepted invitation" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()

      {:ok, invitation} =
        Entities.invite_member(admin_scope, "member@example.com", "member")

      member = user_fixture(%{email: "member@example.com"})
      {:ok, _} = Entities.accept_invitation(member, invitation.token)

      assert :error =
               Entities.get_invitation_by_encoded_token(Invitation.encode_token(invitation.token))
    end
  end

  describe "reusable invite sessions" do
    import Argus.AccountsFixtures

    defp open_session(role \\ "member") do
      admin = Argus.EntitiesFixtures.entity_scope_fixture()
      {:ok, inv} = Entities.open_invite_session(admin, role)
      %{admin: admin, inv: inv}
    end

    test "two different users can accept the same reusable token" do
      %{admin: admin, inv: inv} = open_session()
      u1 = username_user_fixture()
      u2 = username_user_fixture()

      assert {:ok, m1} = Entities.accept_invitation(u1, inv.token)
      assert m1.role == "member"
      assert {:ok, _m2} = Entities.accept_invitation(u2, inv.token)

      assert {:ok, _} =
               Entities.get_invitation_by_encoded_token(
                 Argus.Entities.Invitation.encode_token(inv.token)
               )

      assert Entities.list_entity_members(admin.entity) |> length() == 3
    end

    test "a re-accept by an existing member is a no-op success" do
      %{inv: inv} = open_session()
      u1 = username_user_fixture()
      {:ok, _} = Entities.accept_invitation(u1, inv.token)
      assert {:ok, :already_member} = Entities.accept_invitation(u1, inv.token)
    end

    test "a closed session rejects new accepts" do
      %{admin: admin, inv: inv} = open_session()
      {:ok, _} = Entities.close_invite_session(admin, inv.id)
      u = username_user_fixture()
      assert {:error, :closed} = Entities.accept_invitation(u, inv.token)
    end
  end
end
