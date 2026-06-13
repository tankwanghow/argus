defmodule Argus.ObligationsFixtures do
  @moduledoc """
  Test helpers for obligations.
  """

  alias Argus.Entities
  alias Argus.Obligations.Type
  alias Argus.Repo

  import Argus.AccountsFixtures

  def type_fixture(%Entities.Entity{} = entity, attrs \\ %{}) do
    defaults = %{
      name: "Type #{System.unique_integer([:positive])}",
      recurring_interval: "none",
      complete_note_required: false,
      complete_documents: "",
      reminder_offsets: ""
    }

    attrs = Enum.into(attrs, defaults)

    %Type{entity_id: entity.id}
    |> Type.changeset(attrs)
    |> Repo.insert!()
  end

  def member_fixture(%Entities.Entity{} = entity) do
    user = user_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Repo.insert!()

    user
  end

  def manager_scope_fixture_on_entity(%Entities.Entity{} = entity) do
    user = user_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: entity.id,
      role: "manager",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Repo.insert!()

    membership = Entities.get_membership!(user, entity)
    Argus.Accounts.Scope.put_entity(Argus.Accounts.Scope.for_user(user), entity, membership)
  end

  def member_scope_on_entity(%Entities.Entity{} = entity) do
    user = user_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Repo.insert!()

    membership = Entities.get_membership!(user, entity)
    Argus.Accounts.Scope.put_entity(Argus.Accounts.Scope.for_user(user), entity, membership)
  end

  def assigned_member_scope_fixture(attrs \\ %{}) do
    manager = Argus.EntitiesFixtures.manager_scope_fixture(attrs)
    member_scope = member_scope_on_entity(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Argus.Obligations.create_obligation(manager, %{
        title: "Assigned task",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-15]
      })

    {member_scope, obligation}
  end

  def recurring_primary_scope_fixture(opts \\ []) do
    interval = Keyword.get(opts, :interval, "monthly")
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    type = type_fixture(manager.entity, recurring_interval: interval)

    {:ok, obligation} =
      Argus.Obligations.create_obligation(manager, %{
        title: "Recurring task",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-01-15]
      })

    {member_scope, obligation}
  end

  def manager_obligation_scope_fixture(attrs \\ %{}) do
    manager = Argus.EntitiesFixtures.manager_scope_fixture(attrs)
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Argus.Obligations.create_obligation(manager, %{
        title: "Manager task",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-15]
      })

    {manager, obligation}
  end

  def recurring_manager_scope_fixture(opts \\ []) do
    interval = Keyword.get(opts, :interval, "monthly")
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity, recurring_interval: interval)

    {:ok, obligation} =
      Argus.Obligations.create_obligation(manager, %{
        title: "Recurring task",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      })

    {manager, obligation}
  end

  def obligation_fixture(scope, attrs \\ %{}) do
    type = type_fixture(scope.entity, Map.get(attrs, :type_attrs, %{}))
    assignee = member_fixture(scope.entity)

    attrs =
      Map.merge(
        %{
          title: "Obligation #{System.unique_integer([:positive])}",
          obligation_type_id: type.id,
          primary_assignee_id: assignee.id,
          due_by: ~D[2026-06-15]
        },
        Map.drop(attrs, [:type_attrs])
      )

    {:ok, obligation} = Argus.Obligations.create_obligation(scope, attrs)
    {scope, obligation}
  end
end
