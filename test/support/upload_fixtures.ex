defmodule Tugas.UploadFixtures do
  @moduledoc false

  alias Tugas.Obligations

  def upload_fixture(filename \\ "test.txt", content \\ "hello", content_type \\ nil) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer()}_#{filename}")
    File.write!(path, content)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: content_type || default_content_type(filename)
    }
  end

  def seed_document(scope, obligation, slot, filename) do
    obligation = Obligations.get_obligation!(scope, obligation.id)

    event =
      Enum.find(obligation.events, &(&1.status == "in_progress")) ||
        Enum.find(obligation.events, &(&1.status == "open"))

    {:ok, doc} =
      Obligations.add_document(
        scope,
        obligation,
        event,
        upload_fixture(filename, "scan"),
        slot
      )

    doc
  end

  defp default_content_type(filename) do
    ext = filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    case ext do
      "pdf" -> "application/pdf"
      "jpg" -> "image/jpeg"
      "jpeg" -> "image/jpeg"
      "png" -> "image/png"
      "mp4" -> "video/mp4"
      _ -> "application/octet-stream"
    end
  end
end
