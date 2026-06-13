defmodule Argus.Obligations.TypeTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations
  alias Argus.Obligations.Type

  import Argus.ObligationsFixtures

  describe "create_type/2 and update_type/3" do
    test "manager creates a custom type scoped to the entity" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()

      assert {:ok, type} =
               Obligations.create_type(manager, %{
                 name: "SST Return",
                 recurring_interval: "quarterly"
               })

      assert type.entity_id == manager.entity.id
      assert type.recurring_interval == "quarterly"
    end

    test "member cannot create a type" do
      member = member_scope_on_entity(Argus.EntitiesFixtures.manager_scope_fixture().entity)

      assert :not_authorise =
               Obligations.create_type(member, %{name: "X", recurring_interval: "none"})
    end

    test "manager updates a custom type" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, name: "Old")

      assert {:ok, updated} = Obligations.update_type(manager, type, %{name: "New"})
      assert updated.name == "New"
    end

    test "system presets are immutable" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()

      preset =
        %Type{entity_id: nil}
        |> Type.changeset(%{name: "EPF Preset", recurring_interval: "monthly"})
        |> Repo.insert!()

      assert :not_authorise = Obligations.update_type(manager, preset, %{name: "Hacked"})
    end
  end

  describe "changeset/2" do
    test "rejects invalid reminder_offsets" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          reminder_offsets: "7, ,abc"
        })

      refute changeset.valid?

      assert "must be comma-separated non-negative integers" in errors_on(changeset).reminder_offsets
    end

    test "normalizes reminder_offsets" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          reminder_offsets: " 7,30,7 ,1 "
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :reminder_offsets) == "1,7,30"
    end

    test "rejects duplicate complete_documents slots" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          complete_documents: "receipt,receipt"
        })

      refute changeset.valid?
      assert "has duplicate slot names" in errors_on(changeset).complete_documents
    end

    test "normalizes complete_documents" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          complete_documents: " receipt , form , payment "
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :complete_documents) == "form,payment,receipt"
    end
  end
end
