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

  describe "role ability matrix (pinned)" do
    # Literal source-of-truth grid. Change a value here ONLY when the role rules
    # change on purpose — an accidental drift in Tugas.Authorization fails this test.
    @can2_matrix [
      # action                     admin  manager  coordinator  member
      {:manage_entity, %{admin: true, manager: false, coordinator: false, member: false}},
      {:manage_types, %{admin: true, manager: true, coordinator: false, member: false}},
      {:create_duty, %{admin: true, manager: true, coordinator: true, member: false}},
      {:edit_duty, %{admin: true, manager: true, coordinator: true, member: false}},
      {:skip, %{admin: true, manager: true, coordinator: false, member: false}},
      {:end_series, %{admin: true, manager: true, coordinator: false, member: false}},
      {:void_document, %{admin: true, manager: true, coordinator: false, member: false}},
      {:mark_completed_in_error,
       %{admin: true, manager: true, coordinator: false, member: false}},
      {:view_todos, %{admin: true, manager: true, coordinator: true, member: true}},
      {:create_todo, %{admin: true, manager: true, coordinator: true, member: true}},
      {:edit_todo, %{admin: true, manager: true, coordinator: true, member: true}},
      {:complete_todo, %{admin: true, manager: true, coordinator: true, member: true}},
      {:delete_todo, %{admin: true, manager: true, coordinator: true, member: true}},
      {:cancel_todo, %{admin: true, manager: true, coordinator: true, member: true}}
    ]

    test "can?/2 is exactly pinned for every role and action" do
      scopes = %{
        admin: entity_scope_fixture(),
        manager: manager_scope_fixture(),
        coordinator: coordinator_scope_fixture(),
        member: member_scope_fixture()
      }

      for {action, expected} <- @can2_matrix, {role, want} <- expected do
        got = Authorization.can?(scopes[role], action)

        assert got == want,
               "can?(#{role}, #{inspect(action)}) expected #{want}, got #{got}"
      end
    end

    test "can?/3 duty work permissions are exactly pinned for every role" do
      other = user_fixture()

      scopes = %{
        admin: entity_scope_fixture(),
        manager: manager_scope_fixture(),
        coordinator: coordinator_scope_fixture(),
        member: member_scope_fixture()
      }

      # per role: {mine, unassigned, others} expected result for each duty action.
      expected = %{
        admin: %{mark_done: {true, true, true}, start_progress: {true, true, true}},
        manager: %{mark_done: {true, true, true}, start_progress: {true, true, true}},
        coordinator: %{mark_done: {true, false, false}, start_progress: {true, true, false}},
        member: %{mark_done: {true, false, false}, start_progress: {true, true, false}}
      }

      for {role, scope} <- scopes do
        duties = [
          {:mine, %Duty{primary_assignee_id: scope.user.id, collaborators: []}},
          {:unassigned, %Duty{primary_assignee_id: nil, collaborators: []}},
          {:others, %Duty{primary_assignee_id: other.id, collaborators: []}}
        ]

        for action <- [:mark_done, :start_progress] do
          {want_mine, want_unassigned, want_others} = expected[role][action]
          wants = %{mine: want_mine, unassigned: want_unassigned, others: want_others}

          for {shape, duty} <- duties do
            got = Authorization.can?(scope, action, duty)

            assert got == wants[shape],
                   "can?(#{role}, #{inspect(action)}, #{shape}) expected #{wants[shape]}, got #{got}"
          end
        end
      end
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
