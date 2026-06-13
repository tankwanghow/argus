defmodule Argus.Obligations.DocumentsTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.EntitiesFixtures
  import Argus.ObligationsFixtures

  describe "add_document/5 and void_document/4" do
    test "voided documents are excluded from completion validation" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      type =
        type_fixture(manager.entity,
          complete_note_required: false,
          complete_documents: "receipt"
        )

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-01-15]
        })

      event = hd(Obligations.list_events(obligation))
      upload = upload_fixture("receipt.pdf")

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload, "receipt")

      assert {:ok, _} =
               Obligations.void_document(manager, obligation, document, %{reason: "wrong scan"})

      assert {:error, {:missing_document, "receipt"}} =
               Obligations.complete(member_scope, obligation, %{})

      upload2 = upload_fixture("receipt2.pdf")

      assert {:ok, _replacement} =
               Obligations.add_document(manager, obligation, event, upload2, "receipt")

      assert {:ok, completed, _} = Obligations.complete(member_scope, obligation, %{})
      assert completed.completed_at
    end

    test "uploader can void own document before done" do
      {scope, obligation} = assigned_member_scope_fixture()
      event = hd(Obligations.list_events(obligation))
      upload = upload_fixture()

      assert {:ok, document} =
               Obligations.add_document(scope, obligation, event, upload, nil)

      assert {:ok, voided} =
               Obligations.void_document(scope, obligation, document, %{})

      assert voided.voided_at
      assert voided.voided_by_id == scope.user.id
    end

    test "member cannot void another user's document" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "Task",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-15]
        })

      event = hd(Obligations.list_events(obligation))

      assert {:ok, document} =
               Obligations.add_document(manager, obligation, event, upload_fixture(), nil)

      assert :not_authorise =
               Obligations.void_document(member_scope, obligation, document, %{})
    end
  end

  defp upload_fixture(filename \\ "test.txt", content \\ "hello") do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer()}_#{filename}")
    File.write!(path, content)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: "text/plain"
    }
  end
end
