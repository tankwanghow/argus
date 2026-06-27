defmodule Tugas.DutiesFixtures do
  @moduledoc """
  Test helpers for duties.
  """

  alias Tugas.Entities
  alias Tugas.Duties.Type
  alias Tugas.Repo

  import Tugas.AccountsFixtures

  def type_fixture(%Entities.Entity{} = entity, attrs \\ %{}) do
    defaults = %{
      name: "Type #{System.unique_integer([:positive])}",
      recurring_interval: "none",
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
    Tugas.Accounts.Scope.put_entity(Tugas.Accounts.Scope.for_user(user), entity, membership)
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
    Tugas.Accounts.Scope.put_entity(Tugas.Accounts.Scope.for_user(user), entity, membership)
  end

  def assigned_member_scope_fixture(attrs \\ %{}) do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture(attrs)
    member_scope = member_scope_on_entity(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Tugas.Duties.create_duty(manager, %{
        title: "Assigned task",
        duty_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Assigned task opened"
      })

    {member_scope, duty}
  end

  def recurring_primary_scope_fixture(opts \\ []) do
    interval = Keyword.get(opts, :interval, "monthly")
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    type = type_fixture(manager.entity, recurring_interval: interval)

    {:ok, duty} =
      Tugas.Duties.create_duty(manager, %{
        title: "Recurring task",
        duty_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-01-15],
        open_note: "Recurring task opened"
      })

    {member_scope, duty}
  end

  def manager_duty_scope_fixture(attrs \\ %{}) do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture(attrs)
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Tugas.Duties.create_duty(manager, %{
        title: "Manager task",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-15],
        open_note: "Manager task opened"
      })

    {manager, duty}
  end

  def recurring_manager_scope_fixture(opts \\ []) do
    interval = Keyword.get(opts, :interval, "monthly")
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity, recurring_interval: interval)

    {:ok, duty} =
      Tugas.Duties.create_duty(manager, %{
        title: "Recurring task",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15],
        open_note: "Recurring task opened"
      })

    {manager, duty}
  end

  def duty_fixture(scope, attrs \\ %{}) do
    type = type_fixture(scope.entity, Map.get(attrs, :type_attrs, %{}))
    assignee = member_fixture(scope.entity)

    attrs =
      Map.merge(
        %{
          title: "Duty #{System.unique_integer([:positive])}",
          duty_type_id: type.id,
          primary_assignee_id: assignee.id,
          due_by: ~D[2026-06-15],
          open_note: "Fixture open note"
        },
        Map.drop(attrs, [:type_attrs])
      )

    {:ok, duty} = Tugas.Duties.create_duty(scope, attrs)
    {scope, duty}
  end
end
