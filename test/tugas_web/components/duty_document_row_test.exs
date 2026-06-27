defmodule TugasWeb.DutyDocumentRowTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import TugasWeb.DutyDocumentRow

  alias Tugas.Duties.EventDocument

  defp doc(id \\ "doc-1") do
    %EventDocument{
      id: id,
      file: %{"original" => "receipt.pdf"},
      inserted_at: ~U[2026-06-15 10:00:00Z]
    }
  end

  defp duty do
    %{id: "obl-1", completed_at: nil, closed_at: nil}
  end

  test "live_actions shows confirm controls while deleting" do
    html =
      render_component(
        &live_actions/1,
        doc: doc(),
        duty: duty(),
        current_scope: %{},
        deleting_document_id: "doc-1",
        id_prefix: "m-"
      )

    assert html =~ ~s(id="m-confirm-delete-doc-doc-1")
    assert html =~ "❌"
  end

  test "void_form includes optional event_id for step-file uploads" do
    html =
      render_component(
        &void_form/1,
        doc: doc(),
        event_id: "event-9",
        void_reason_required?: false,
        id_prefix: ""
      )

    assert html =~ ~s(name="event_id" value="event-9")
    assert html =~ "Confirm void"
  end

  test "voided_row can show the document slot badge" do
    doc = %{doc() | document_slot: "receipt", void_reason: "wrong scan"}

    html =
      render_component(
        &voided_row/1,
        doc: doc,
        entity_slug: "acme",
        duty: duty(),
        show_slot_badge?: true
      )

    assert html =~ "receipt"
    assert html =~ "voided"
    assert html =~ "Void reason: wrong scan"
  end
end
