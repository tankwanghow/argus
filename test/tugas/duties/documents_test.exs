defmodule Tugas.Duties.DocumentsTest do
  use Tugas.DataCase, async: true

  alias Tugas.Duties

  import Tugas.EntitiesFixtures
  import Tugas.DutiesFixtures
  import Tugas.UploadFixtures

  describe "add_document/5 and void_document/4" do
    test "voided documents are excluded from completion validation" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF Jan",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Duties.list_events(duty))
      upload = upload_fixture("receipt.pdf")

      assert {:ok, document} =
               Duties.add_document(manager, duty, event, upload, "receipt")

      assert {:ok, _} = Duties.delete_document(manager, duty, document)

      assert {:error, {:missing_document, "receipt"}} =
               Duties.complete(member_scope, duty, %{note: "Done"})

      upload2 = upload_fixture("receipt2.pdf")

      assert {:ok, _replacement} =
               Duties.add_document(manager, duty, event, upload2, "receipt")

      assert {:ok, completed, _} =
               Duties.complete(member_scope, duty, %{note: "Done"})

      assert completed.completed_at
    end

    test "slotless uploads are allowed alongside required slot documents" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF Jan",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, extra} =
               Duties.add_document(
                 manager,
                 duty,
                 event,
                 upload_fixture("notes.pdf"),
                 nil
               )

      assert is_nil(extra.document_slot)

      assert {:ok, receipt} =
               Duties.add_document(
                 manager,
                 duty,
                 event,
                 upload_fixture("receipt.pdf"),
                 "receipt"
               )

      assert receipt.document_slot == "receipt"

      assert {:ok, completed, _} =
               Duties.complete(member_scope, duty, %{note: "Done"})

      assert completed.completed_at
    end

    test "slotless uploads alone do not satisfy required slots" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF Jan",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, _} =
               Duties.add_document(
                 manager,
                 duty,
                 event,
                 upload_fixture("notes.pdf"),
                 nil
               )

      assert {:error, {:missing_document, "receipt"}} =
               Duties.complete(member_scope, duty, %{note: "Done"})
    end

    test "uploader can delete own document within 48 hours" do
      {scope, duty} = assigned_member_scope_fixture()
      event = hd(Duties.list_events(duty))
      upload = upload_fixture()

      assert {:ok, document} =
               Duties.add_document(scope, duty, event, upload, nil)

      assert {:ok, _} = Duties.delete_document(scope, duty, document)
      refute Tugas.Repo.get(Tugas.Duties.EventDocument, document.id)
    end

    test "files on old slot names are ignored for Done after slots change" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF Jan",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, _old_receipt} =
               Duties.add_document(manager, duty, event, upload_fixture(), "receipt")

      {:ok, _type} =
        Tugas.Duties.update_type(manager, type, %{complete_documents: "payment_receipt"})

      synced = Tugas.Repo.get!(Tugas.Duties.Duty, duty.id)
      assert synced.complete_documents == "payment_receipt"

      assert {:ok, _new_receipt} =
               Duties.add_document(
                 manager,
                 synced,
                 event,
                 upload_fixture("payment.pdf"),
                 "payment_receipt"
               )

      assert {:ok, completed, _} =
               Duties.complete(member_scope, synced, %{note: "Done"})

      assert completed.completed_at
    end

    test "document can be deleted within 48 hours on a live cycle" do
      manager = manager_scope_fixture()

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "Task",
          duty_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, document} =
               Duties.add_document(manager, duty, event, upload_fixture(), nil)

      assert {:ok, _} = Duties.delete_document(manager, duty, document)
      refute Tugas.Repo.get(Tugas.Duties.EventDocument, document.id)
    end

    test "document cannot be deleted after 48 hours on a live cycle" do
      manager = manager_scope_fixture()

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "Task",
          duty_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, document} =
               Duties.add_document(manager, duty, event, upload_fixture(), nil)

      old =
        document
        |> Ecto.Changeset.change(
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
        )
        |> Tugas.Repo.update!()

      assert :not_authorise = Duties.delete_document(manager, duty, old)
      assert Tugas.Repo.get!(Tugas.Duties.EventDocument, old.id)
    end

    test "void is required after 48 hours on a live cycle" do
      manager = manager_scope_fixture()

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "Task",
          duty_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, document} =
               Duties.add_document(manager, duty, event, upload_fixture(), nil)

      old =
        document
        |> Ecto.Changeset.change(
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
        )
        |> Tugas.Repo.update!()

      refute Duties.document_deletable?(manager, duty, old)
      assert Duties.document_voidable?(manager, duty, old)

      assert {:ok, voided} = Duties.void_document(manager, duty, old, %{})
      assert voided.voided_at
    end

    test "member cannot void another user's document" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "Task",
          duty_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Duties.list_events(duty))

      assert {:ok, document} =
               Duties.add_document(manager, duty, event, upload_fixture(), nil)

      old =
        document
        |> Ecto.Changeset.change(
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
        )
        |> Tugas.Repo.update!()

      assert :not_authorise =
               Duties.void_document(member_scope, duty, old, %{})
    end
  end
end
