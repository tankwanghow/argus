defmodule Tugas.Uploads.FileKind do
  @moduledoc false

  @image_exts ~w(jpg jpeg png gif webp svg avif bmp heic heif)
  @video_exts ~w(mp4 webm mov ogg ogv m4v)

  @doc """
  Classifies a filename (and optional MIME type) into `:image`, `:video`, `:pdf`, or `:other`.
  """
  def classify(name, content_type \\ nil)

  def classify(name, content_type) when is_binary(name) do
    ext = name |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    cond do
      ext in @image_exts -> :image
      ext in @video_exts -> :video
      ext == "pdf" -> :pdf
      ext == "" -> classify_content_type(content_type)
      true -> :other
    end
  end

  def classify(_name, content_type), do: classify_content_type(content_type)

  defp classify_content_type(type) when is_binary(type) do
    cond do
      String.starts_with?(type, "image/") -> :image
      String.starts_with?(type, "video/") -> :video
      type == "application/pdf" -> :pdf
      true -> :other
    end
  end

  defp classify_content_type(_), do: :other
end
