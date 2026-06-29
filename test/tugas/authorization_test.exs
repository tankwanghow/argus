defmodule Tugas.AuthorizationTest do
  use Tugas.DataCase, async: true

  alias Tugas.Authorization
  alias Tugas.Duties.Duty

  import Tugas.AccountsFixtures
  import Tugas.EntitiesFixtures

  describe "can?/2" do
    test "manager can create duty" do
      scope = manager_scope_fixture()
      assert Authorization.can?(scope, :create_duty)
    end

    test "manager can skip" do
      scope = manager_scope_fixture()
      assert Authorization.can?(scope, :skip)
    end

    test "member cannot skip" do
      scope = member_scope_fixture()
      refute Authorization.can?(scope, :skip)
    end

    test "admin can manage entity" do
      scope = entity_scope_fixture()
      assert Authorization.can?(scope, :manage_entity)
    end

    test "manager cannot manage entity" do
      scope = manager_scope_fixture()
      refute Authorization.can?(scope, :manage_entity)
    end

    test "manager can manage types" do
      scope = manager_scope_fixture()
      assert Authorization.can?(scope, :manage_types)
    end

    test "member cannot manage types" do
      scope = member_scope_fixture()
      refute Authorization.can?(scope, :manage_types)
    end
  end

  describe "coordinator role" do
    test "can create and edit duties" do
      scope = coordinator_scope_fixture()
      assert Authorization.can?(scope, :create_duty)
      assert Authorization.can?(scope, :edit_duty)
    end

    test "cannot manage types, entity, or manager-only duty actions" do
      scope = coordinator_scope_fixture()

      refute Authorization.can?(scope, :manage_types)
      refute Authorization.can?(scope, :manage_entity)
      refute Authorization.can?(scope, :skip)
      refute Authorization.can?(scope, :end_series)
      refute Authorization.can?(scope, :void_document)
      refute Authorization.can?(scope, :mark_completed_in_error)
    end

    test "can manage todos" do
      scope = coordinator_scope_fixture()
      assert Authorization.can?(scope, :create_todo)
      assert Authorization.can?(scope, :view_todos)
    end

    test "work permissions match member — primary assignee marks done, any member on unassigned" do
      scope = coordinator_scope_fixture()
      other = user_fixture()

      assigned = %Duty{primary_assignee_id: scope.user.id, collaborators: []}
      unassigned = %Duty{primary_assignee_id: nil, collaborators: []}
      others = %Duty{primary_assignee_id: other.id, collaborators: []}

      assert Authorization.can?(scope, :mark_done, assigned)
      refute Authorization.can?(scope, :mark_done, unassigned)
      refute Authorization.can?(scope, :mark_done, others)

      assert Authorization.can?(scope, :start_progress, unassigned)
      assert Authorization.can?(scope, :start_progress, assigned)
      refute Authorization.can?(scope, :start_progress, others)
    end
  end

  describe "can?/3" do
    test "collaborator cannot mark done" do
      {scope, duty} = collaborator_scope_fixture()
      refute Authorization.can?(scope, :mark_done, duty)
    end

    test "primary assignee member can mark done" do
      {scope, duty} = primary_assignee_scope_fixture()
      assert Authorization.can?(scope, :mark_done, duty)
    end

    test "collaborator can start progress" do
      {scope, duty} = collaborator_scope_fixture()
      assert Authorization.can?(scope, :start_progress, duty)
    end

    test "non-assignee member cannot start progress" do
      scope = member_scope_fixture()
      other = user_fixture()

      duty = %Duty{
        primary_assignee_id: other.id,
        collaborators: []
      }

      refute Authorization.can?(scope, :start_progress, duty)
    end

    test "any member can start progress on unassigned duty" do
      scope = member_scope_fixture()

      duty = %Duty{
        primary_assignee_id: nil,
        collaborators: []
      }

      assert Authorization.can?(scope, :start_progress, duty)
    end

    test "member cannot mark done on unassigned duty" do
      scope = member_scope_fixture()

      duty = %Duty{
        primary_assignee_id: nil,
        collaborators: []
      }

      refute Authorization.can?(scope, :mark_done, duty)
    end

    test "manager can mark done on unassigned duty" do
      scope = manager_scope_fixture()

      duty = %Duty{
        primary_assignee_id: nil,
        collaborators: []
      }

      assert Authorization.can?(scope, :mark_done, duty)
    end
  end

  describe "mark_completed_in_error" do
    test "admin and manager may, member may not" do
      assert Authorization.can?(entity_scope_fixture(), :mark_completed_in_error)
      assert Authorization.can?(manager_scope_fixture(), :mark_completed_in_error)
      refute Authorization.can?(member_scope_fixture(), :mark_completed_in_error)
    end
  end

  defp collaborator_scope_fixture do
    admin_scope = entity_scope_fixture()
    collaborator = user_fixture()

    %Tugas.Entities.Membership{
      user_id: collaborator.id,
      entity_id: admin_scope.entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Tugas.Entities.Membership.changeset(%{})
    |> Tugas.Repo.insert!()

    membership = Tugas.Entities.get_membership!(collaborator, admin_scope.entity)

    scope =
      Tugas.Accounts.Scope.put_entity(
        Tugas.Accounts.Scope.for_user(collaborator),
        admin_scope.entity,
        membership
      )

    primary = user_fixture()

    duty = %Duty{
      primary_assignee_id: primary.id,
      collaborators: [%{user_id: collaborator.id}]
    }

    {scope, duty}
  end

  defp primary_assignee_scope_fixture do
    scope = member_scope_fixture()

    duty = %Duty{
      primary_assignee_id: scope.user.id,
      collaborators: []
    }

    {scope, duty}
  end
end
