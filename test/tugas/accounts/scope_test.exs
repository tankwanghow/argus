defmodule Tugas.Accounts.ScopeTest do
  use Tugas.DataCase, async: true

  alias Tugas.Accounts.Scope
  alias Tugas.Entities.{Entity, Membership}

  import Tugas.AccountsFixtures

  test "put_entity/3 sets entity, membership and role" do
    scope = Scope.for_user(user_fixture())
    entity = %Entity{id: Ecto.UUID.generate(), slug: "acme", name: "Acme"}
    membership = %Membership{role: "admin", accepted_at: DateTime.utc_now(:second)}

    scope = Scope.put_entity(scope, entity, membership)

    assert scope.entity == entity
    assert scope.role == :admin
  end
end
