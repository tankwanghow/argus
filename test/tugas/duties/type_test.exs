defmodule Tugas.Duties.TypeTest do
  use Tugas.DataCase, async: true

  alias Tugas.Duties
  alias Tugas.Duties.Type

  import Tugas.DutiesFixtures

  describe "create_type/2 and update_type/3" do
    test "manager creates a custom type scoped to the entity" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()

      assert {:ok, type} =
               Duties.create_type(manager, %{
                 name: "Custom filing",
                 recurring_interval: "quarterly"
               })

      assert type.entity_id == manager.entity.id
      assert type.recurring_interval == "quarterly"
    end

    test "member cannot create a type" do
      member = member_scope_on_entity(Tugas.EntitiesFixtures.manager_scope_fixture().entity)

      assert :not_authorise =
               Duties.create_type(member, %{name: "X", recurring_interval: "none"})
    end

    test "manager updates a custom type" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, name: "Old")

      assert {:ok, updated} = Duties.update_type(manager, type, %{name: "New"})
      assert updated.name == "New"
    end

    test "manager cannot update another entity's type" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      other_entity = Tugas.EntitiesFixtures.entity_fixture()
      type = type_fixture(other_entity, name: "Other type")

      assert :not_authorise = Duties.update_type(manager, type, %{name: "Hacked"})
    end

    test "updating complete_documents propagates to all live duties of the type" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "")

      {:ok, live_one} =
        Duties.create_duty(manager, %{
          title: "EPF Jan",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      {:ok, live_two} =
        Duties.create_duty(manager, %{
          title: "EPF Feb",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-02-15],
          open_note: "Open"
        })

      assert {:ok, done, _} =
               Duties.complete(member_scope, live_one, %{note: "Done"})

      assert {:ok, _type} =
               Duties.update_type(manager, type, %{complete_documents: "payment_receipt"})

      assert Tugas.Repo.get!(Tugas.Duties.Duty, live_two.id).complete_documents ==
               "payment_receipt"

      assert Tugas.Repo.get!(Tugas.Duties.Duty, done.id).complete_documents == ""
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
