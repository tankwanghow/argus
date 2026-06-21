defmodule ArgusWeb.DoneDocumentChecklistTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ArgusWeb.DoneDocumentChecklist

  alias Argus.Obligations.EventDocument

  test "renders a missing required slot (nil value) without crashing" do
    html = render_component(&done_document_checklist/1, required_docs: [{"PCB Form", nil}])

    assert html =~ "PCB Form"
    assert html =~ "Missing"
  end

  test "renders a satisfied required slot (document struct value) without crashing" do
    html =
      render_component(&done_document_checklist/1,
        required_docs: [{"PCB Form", %EventDocument{}}]
      )

    assert html =~ "PCB Form"
    assert html =~ "Uploaded"
    assert html =~ "All required documents are uploaded."
  end
end
