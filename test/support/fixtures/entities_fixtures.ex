defmodule Tugas.EntitiesFixtures do
  @moduledoc """
  Test helpers for entities and scoped fixtures.
  """

  alias Tugas.Accounts.Scope
  alias Tugas.Entities

  import Tugas.AccountsFixtures

  def entity_fixture(scope \\ nil, attrs \\ %{}) do
    scope = scope || Scope.for_user(user_fixture())

    attrs =
      Enum.into(attrs, %{
        slug: "entity-#{System.unique_integer([:positive])}",
        name: "Entity #{System.unique_integer([:positive])}"
      })

    {:ok, entity} = Entities.create_entity(scope, attrs)
    entity
  end

  def entity_scope_fixture(attrs \\ %{}) do
    scope = Scope.for_user(user_fixture())
    entity = entity_fixture(scope, attrs)
    membership = Entities.get_membership!(scope.user, entity)
    Scope.put_entity(scope, entity, membership)
  end

  def manager_scope_fixture(attrs \\ %{}) do
    admin_scope = entity_scope_fixture(attrs)
    manager = user_fixture()

    %Tugas.Entities.Membership{
      user_id: manager.id,
      entity_id: admin_scope.entity.id,
      role: "manager",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Tugas.Entities.Membership.changeset(%{})
    |> Tugas.Repo.insert!()

    membership = Entities.get_membership!(manager, admin_scope.entity)
    Scope.put_entity(Scope.for_user(manager), admin_scope.entity, membership)
  end

  def coordinator_scope_fixture(attrs \\ %{}) do
    admin_scope = entity_scope_fixture(attrs)
    coordinator = user_fixture()

    %Tugas.Entities.Membership{
      user_id: coordinator.id,
      entity_id: admin_scope.entity.id,
      role: "coordinator",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Tugas.Entities.Membership.changeset(%{})
    |> Tugas.Repo.insert!()

    membership = Entities.get_membership!(coordinator, admin_scope.entity)
    Scope.put_entity(Scope.for_user(coordinator), admin_scope.entity, membership)
  end

  def member_scope_fixture(attrs \\ %{}) do
    admin_scope = entity_scope_fixture(attrs)
    member = user_fixture()

    %Tugas.Entities.Membership{
      user_id: member.id,
      entity_id: admin_scope.entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Tugas.Entities.Membership.changeset(%{})
    |> Tugas.Repo.insert!()

    membership = Entities.get_membership!(member, admin_scope.entity)
    Scope.put_entity(Scope.for_user(member), admin_scope.entity, membership)
  end
end
