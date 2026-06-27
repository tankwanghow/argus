defmodule Argus.EntitiesTest do
  use Argus.DataCase, async: true

  alias Argus.Accounts.Scope
  alias Argus.Entities
  alias Argus.Entities.Membership
  alias Argus.Obligations
  alias Argus.Obligations.SampleTypes

  import Argus.AccountsFixtures
  import Argus.EntitiesFixtures
  import Argus.ObligationsFixtures

  describe "disable_member/2 and enable_member/2" do
    test "admin disables a member, stamping disabled_at and freeing a seat" do
      admin_scope = entity_scope_fixture(%{seat_limit: 2})
      member = member_scope_on_entity(admin_scope.entity)

      assert {:ok, disabled} = Entities.disable_member(admin_scope, member.membership)
      assert disabled.disabled_at
      assert disabled.disabled_by_id == admin_scope.user.id

      # admin + member filled 2 seats; disabling frees one
      assert Entities.seats_available?(admin_scope.entity)
    end

    test "disabling auto-unassigns the member's live primary duties with an audit row" do
      admin_scope = entity_scope_fixture()
      member = member_scope_on_entity(admin_scope.entity)
      obligation = live_obligation_assigned_to(admin_scope, member.user.id)

      assert {:ok, _} = Entities.disable_member(admin_scope, member.membership)

      reloaded = Argus.Repo.get!(Argus.Obligations.Obligation, obligation.id)
      assert is_nil(reloaded.primary_assignee_id)

      audit = Obligations.list_audit_logs(reloaded)
      assert Enum.any?(audit, &(&1.field == "primary_assignee" and is_nil(&1.new_value)))
    end

    test "disabling removes the member's collaborator rows on live obligations" do
      admin_scope = entity_scope_fixture()
      member = member_scope_on_entity(admin_scope.entity)
      other = live_obligation_assigned_to(admin_scope, nil)

      {:ok, _} = Obligations.update_collaborators(admin_scope, other, [member.user.id])
      assert member.user.id in collaborator_ids(other)

      assert {:ok, _} = Entities.disable_member(admin_scope, member.membership)
      refute member.user.id in collaborator_ids(other)
    end

    test "manager cannot disable a member" do
      admin_scope = entity_scope_fixture()
      manager = manager_scope_fixture_on_entity(admin_scope.entity)
      member = member_scope_on_entity(admin_scope.entity)

      assert :not_authorise = Entities.disable_member(manager, member.membership)
    end

    test "cannot disable yourself" do
      admin_scope = entity_scope_fixture()
      membership = Entities.get_membership!(admin_scope.user, admin_scope.entity)

      assert {:error, :cannot_disable_self} = Entities.disable_member(admin_scope, membership)
    end

    test "cannot disable the last active admin" do
      admin_scope = entity_scope_fixture()
      second_admin_membership = add_admin(admin_scope.entity)

      # two admins -> disabling the second is allowed
      assert {:ok, _} = Entities.disable_member(admin_scope, second_admin_membership)

      # only one active admin remains; the self-guard blocks disabling it
      remaining = Entities.get_membership!(admin_scope.user, admin_scope.entity)
      assert {:error, :cannot_disable_self} = Entities.disable_member(admin_scope, remaining)
    end

    test "membership from another entity is rejected" do
      admin_scope = entity_scope_fixture()
      other_scope = entity_scope_fixture()
      foreign = Entities.get_membership!(other_scope.user, other_scope.entity)

      assert :not_found = Entities.disable_member(admin_scope, foreign)
    end

    test "enable re-checks the seat limit and rejects when full" do
      admin_scope = entity_scope_fixture(%{seat_limit: 2})
      member = member_scope_on_entity(admin_scope.entity)

      {:ok, disabled} = Entities.disable_member(admin_scope, member.membership)
      # fill the freed seat with another active member
      member_scope_on_entity(admin_scope.entity)

      assert {:error, :seat_limit_reached} = Entities.enable_member(admin_scope, disabled)
    end

    test "enable clears disabled_at when a seat is available" do
      admin_scope = entity_scope_fixture(%{seat_limit: 5})
      member = member_scope_on_entity(admin_scope.entity)

      {:ok, disabled} = Entities.disable_member(admin_scope, member.membership)
      assert {:ok, enabled} = Entities.enable_member(admin_scope, disabled)
      assert is_nil(enabled.disabled_at)
      assert is_nil(enabled.disabled_by_id)
    end

    test "list_entity_memberships hides entities the user is disabled in" do
      admin_scope = entity_scope_fixture()
      member = member_scope_on_entity(admin_scope.entity)

      assert admin_scope.entity.id in entity_ids(Entities.list_entity_memberships(member.user))

      {:ok, _} = Entities.disable_member(admin_scope, member.membership)

      refute admin_scope.entity.id in entity_ids(Entities.list_entity_memberships(member.user))
    end

    test "list_member_administration includes disabled members with assignment counts" do
      admin_scope = entity_scope_fixture()
      member = member_scope_on_entity(admin_scope.entity)
      _obligation = live_obligation_assigned_to(admin_scope, member.user.id)

      {:ok, _} = Entities.disable_member(admin_scope, member.membership)

      rows = Entities.list_member_administration(admin_scope.entity)
      member_row = Enum.find(rows, fn {u, _m, _c} -> u.id == member.user.id end)

      assert {_user, membership, counts} = member_row
      assert membership.disabled_at
      # the auto-unassign on disable cleared the live primary duty
      assert counts == %{primary: 0, collaborations: 0}
    end
  end

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

    test "disabled members do not count toward seats" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture(%{seat_limit: 2})
      disabled_user = user_fixture()

      %Membership{
        user_id: disabled_user.id,
        entity_id: admin_scope.entity.id,
        role: "member",
        accepted_at: DateTime.utc_now(:second),
        disabled_at: DateTime.utc_now(:second)
      }
      |> Membership.changeset(%{})
      |> Argus.Repo.insert!()

      # admin (active) + disabled member = 1 active of 2 seats -> still a free seat
      assert Entities.seats_available?(admin_scope.entity)
    end

    test "list_entity_members excludes disabled members" do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()
      disabled_user = user_fixture(%{email: "disabled@example.com"})

      %Membership{
        user_id: disabled_user.id,
        entity_id: admin_scope.entity.id,
        role: "member",
        accepted_at: DateTime.utc_now(:second),
        disabled_at: DateTime.utc_now(:second)
      }
      |> Membership.changeset(%{})
      |> Argus.Repo.insert!()

      emails =
        Entities.list_entity_members(admin_scope.entity) |> Enum.map(fn {u, _} -> u.email end)

      refute "disabled@example.com" in emails
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

  defp add_admin(entity) do
    user = user_fixture()

    %Membership{
      user_id: user.id,
      entity_id: entity.id,
      role: "admin",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Membership.changeset(%{})
    |> Argus.Repo.insert!()

    Entities.get_membership!(user, entity)
  end

  defp live_obligation_assigned_to(scope, assignee_id) do
    type = type_fixture(scope.entity)

    {:ok, obligation} =
      Obligations.create_obligation(scope, %{
        title: "Duty #{System.unique_integer([:positive])}",
        obligation_type_id: type.id,
        primary_assignee_id: assignee_id,
        due_by: ~D[2026-06-15],
        open_note: "opened"
      })

    obligation
  end

  defp collaborator_ids(obligation) do
    import Ecto.Query

    Argus.Obligations.Collaborator
    |> where([c], c.obligation_id == ^obligation.id)
    |> Argus.Repo.all()
    |> Enum.map(& &1.user_id)
  end

  defp entity_ids(memberships), do: Enum.map(memberships, fn {entity, _m} -> entity.id end)
end
