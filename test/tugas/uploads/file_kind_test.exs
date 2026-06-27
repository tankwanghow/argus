defmodule Tugas.Uploads.FileKindTest do
  use ExUnit.Case, async: true

  alias Tugas.Uploads.FileKind

  test "classify/1 groups common extensions" do
    assert FileKind.classify("photo.JPG") == :image
    assert FileKind.classify("clip.mp4") == :video
    assert FileKind.classify("report.pdf") == :pdf
    assert FileKind.classify("notes.txt") == :other
    assert FileKind.classify("IMG_1234.HEIC") == :image
    assert FileKind.classify("photo.heif") == :image
  end

  test "classify/2 falls back to MIME type when extension is missing" do
    assert FileKind.classify("blob", "image/jpeg") == :image
    assert FileKind.classify("blob", "video/mp4") == :video
    assert FileKind.classify("blob", "application/pdf") == :pdf
    assert FileKind.classify("blob", "text/plain") == :other
  end
end
