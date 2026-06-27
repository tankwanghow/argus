defmodule Tugas.UploadFixtures do
  @moduledoc false

  alias Tugas.Duties

  def upload_fixture(filename \\ "test.txt", content \\ "hello", content_type \\ nil) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer()}_#{filename}")
    File.write!(path, content)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: content_type || default_content_type(filename)
    }
  end

  def seed_document(scope, duty, slot, filename) do
    duty = Duties.get_duty!(scope, duty.id)

    event =
      Enum.find(duty.events, &(&1.status == "in_progress")) ||
        Enum.find(duty.events, &(&1.status == "open"))

    {:ok, doc} =
      Duties.add_document(
        scope,
        duty,
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
