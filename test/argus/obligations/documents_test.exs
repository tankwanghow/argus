defmodule Argus.Obligations.DocumentsTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.EntitiesFixtures
  import Argus.ObligationsFixtures
  import Argus.UploadFixtures

  describe "add_document/5 and void_document/4" do
    test "voided documents are excluded from completion validation" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Obligations.list_events(obligation))
      upload = upload_fixture("receipt.pdf")

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload, "receipt")

      assert {:ok, _} = Obligations.delete_document(manager, obligation, document)

      assert {:error, {:missing_document, "receipt"}} =
               Obligations.complete(member_scope, obligation, %{note: "Done"})

      upload2 = upload_fixture("receipt2.pdf")

      assert {:ok, _replacement} =
               Obligations.add_document(manager, obligation, event, upload2, "receipt")

      assert {:ok, completed, _} =
               Obligations.complete(member_scope, obligation, %{note: "Done"})

      assert completed.completed_at
    end

    test "slotless uploads are allowed alongside required slot documents" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, extra} =
               Obligations.add_document(
                 manager,
                 obligation,
                 event,
                 upload_fixture("notes.pdf"),
                 nil
               )

      assert is_nil(extra.document_slot)

      assert {:ok, receipt} =
               Obligations.add_document(
                 manager,
                 obligation,
                 event,
                 upload_fixture("receipt.pdf"),
                 "receipt"
               )

      assert receipt.document_slot == "receipt"

      assert {:ok, completed, _} =
               Obligations.complete(member_scope, obligation, %{note: "Done"})

      assert completed.completed_at
    end

    test "slotless uploads alone do not satisfy required slots" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, _} =
               Obligations.add_document(
                 manager,
                 obligation,
                 event,
                 upload_fixture("notes.pdf"),
                 nil
               )

      assert {:error, {:missing_document, "receipt"}} =
               Obligations.complete(member_scope, obligation, %{note: "Done"})
    end

    test "uploader can delete own document within 48 hours" do
      {scope, obligation} = assigned_member_scope_fixture()
      event = hd(Obligations.list_events(obligation))
      upload = upload_fixture()

      assert {:ok, document} =
               Obligations.add_document(scope, obligation, event, upload, nil)

      assert {:ok, _} = Obligations.delete_document(scope, obligation, document)
      refute Argus.Repo.get(Argus.Obligations.EventDocument, document.id)
    end

    test "files on old slot names are ignored for Done after slots change" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15],
          open_note: "Open"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, _old_receipt} =
               Obligations.add_document(manager, obligation, event, upload_fixture(), "receipt")

      {:ok, _type} =
        Argus.Obligations.update_type(manager, type, %{complete_documents: "payment_receipt"})

      synced = Argus.Repo.get!(Argus.Obligations.Obligation, obligation.id)
      assert synced.complete_documents == "payment_receipt"

      assert {:ok, _new_receipt} =
               Obligations.add_document(
                 manager,
                 synced,
                 event,
                 upload_fixture("payment.pdf"),
                 "payment_receipt"
               )

      assert {:ok, completed, _} =
               Obligations.complete(member_scope, synced, %{note: "Done"})

      assert completed.completed_at
    end

    test "document can be deleted within 48 hours on a live cycle" do
      manager = manager_scope_fixture()

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "Task",
          obligation_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload_fixture(), nil)

      assert {:ok, _} = Obligations.delete_document(manager, obligation, document)
      refute Argus.Repo.get(Argus.Obligations.EventDocument, document.id)
    end

    test "document cannot be deleted after 48 hours on a live cycle" do
      manager = manager_scope_fixture()

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "Task",
          obligation_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload_fixture(), nil)

      old =
        document
        |> Ecto.Changeset.change(
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
        )
        |> Argus.Repo.update!()

      assert :not_authorise = Obligations.delete_document(manager, obligation, old)
      assert Argus.Repo.get!(Argus.Obligations.EventDocument, old.id)
    end

    test "void is required after 48 hours on a live cycle" do
      manager = manager_scope_fixture()

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "Task",
          obligation_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload_fixture(), nil)

      old =
        document
        |> Ecto.Changeset.change(
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
        )
        |> Argus.Repo.update!()

      refute Obligations.document_deletable?(manager, obligation, old)
      assert Obligations.document_voidable?(manager, obligation, old)

      assert {:ok, voided} = Obligations.void_document(manager, obligation, old, %{})
      assert voided.voided_at
    end

    test "member cannot void another user's document" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "Task",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-15],
          open_note: "Task opened"
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload_fixture(), nil)

      old =
        document
        |> Ecto.Changeset.change(
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
        )
        |> Argus.Repo.update!()

      assert :not_authorise =
               Obligations.void_document(member_scope, obligation, old, %{})
    end
  end
end
