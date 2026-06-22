defmodule ArgusWeb.ObligationLive.DocumentHelpersTest do
  use ExUnit.Case, async: true

  alias ArgusWeb.ObligationLive.DocumentHelpers, as: H
  alias Argus.Obligations.EventDocument

  defp doc(slot, voided? \\ false) do
    %EventDocument{
      id: Ecto.UUID.generate(),
      document_slot: slot,
      voided_at: if(voided?, do: ~U[2026-06-16 08:33:00Z], else: nil)
    }
  end

  test "parse_slots splits and trims, dropping blanks" do
    assert H.parse_slots("receipt, form ,") == ["receipt", "form"]
    assert H.parse_slots("") == []
    assert H.parse_slots(nil) == []
  end

  test "completion_view maps each required slot to its live file or nil" do
    receipt = doc("receipt")
    form_voided = doc("form", true)
    other = doc(nil)

    {slot_rows, voided_required} =
      H.completion_view([receipt, form_voided, other], ["receipt", "form"])

    assert slot_rows == [{"receipt", receipt}, {"form", nil}]
    assert voided_required == [form_voided]
  end

  test "file_kind classifies by filename extension (case-insensitive)" do
    assert H.file_kind("photo.JPG") == :image
    assert H.file_kind("scan.png") == :image
    assert H.file_kind("animation.webp") == :image
    assert H.file_kind("clip.mp4") == :video
    assert H.file_kind("movie.MOV") == :video
    assert H.file_kind("receipt.pdf") == :pdf
    assert H.file_kind("report.docx") == :other
    assert H.file_kind("archive.zip") == :other
    assert H.file_kind("noextension") == :other
    assert H.file_kind(nil) == :other
  end

  test "step_files returns this event's live and voided other files (slot nil or stale)" do
    live_no_slot = doc(nil)
    live_stale = doc("old_slot")
    live_required = doc("receipt")
    voided_no_slot = doc(nil, true)
    voided_required = doc("receipt", true)

    {live_other, voided_other} =
      H.step_files(
        [live_no_slot, live_stale, live_required, voided_no_slot, voided_required],
        ["receipt"]
      )

    assert live_other == [live_no_slot, live_stale]
    assert voided_other == [voided_no_slot]
  end
end
