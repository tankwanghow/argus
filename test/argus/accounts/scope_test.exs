defmodule Argus.Accounts.ScopeTest do
  use Argus.DataCase, async: true

  alias Argus.Accounts.Scope
  alias Argus.Entities.{Entity, Membership}

  import Argus.AccountsFixtures

  test "put_entity/3 sets entity, membership and role" do
    scope = Scope.for_user(user_fixture())
    entity = %Entity{id: Ecto.UUID.generate(), slug: "acme", name: "Acme"}
    membership = %Membership{role: "admin", accepted_at: DateTime.utc_now(:second)}

    scope = Scope.put_entity(scope, entity, membership)

    assert scope.entity == entity
    assert scope.role == :admin
  end
end