defmodule Tugas.Uploads do
  @moduledoc """
  Local filesystem storage for duty event documents.
  """

  alias Tugas.Uploads.Limits

  def store(%Plug.Upload{} = upload, entity_id, duty_id) do
    with :ok <- validate_upload_size(upload) do
      dest_dir = Path.join([base_dir(), to_string(entity_id), to_string(duty_id)])
      File.mkdir_p!(dest_dir)
      safe_name = upload.filename |> Path.basename() |> sanitize_filename()
      filename = "#{Ecto.UUID.generate()}_#{safe_name}"
      dest = Path.join(dest_dir, filename)
      File.cp!(upload.path, dest)
      %{filename: filename, original: safe_name, path: dest}
    end
  end

  defp validate_upload_size(%Plug.Upload{path: path, filename: filename, content_type: type}) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        case Limits.validate_size(filename, size, type) do
          :ok -> :ok
          {:error, _} -> {:error, :file_too_large}
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  def delete(%{file: file}) when is_map(file) do
    case file_path(file) do
      path when is_binary(path) -> File.rm(path)
      _ -> :ok
    end
  end

  def delete(_), do: :ok

  def path(%{file: file}) when is_map(file), do: file_path(file)

  defp base_dir do
    Application.get_env(:tugas, :uploads_dir, Path.join(:code.priv_dir(:tugas), "uploads"))
  end

  defp file_path(file) do
    Map.get(file, "path") || Map.get(file, :path)
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w.\-]/, "_")
    |> String.trim_leading(".")
    |> case do
      "" -> "upload"
      safe -> safe
    end
  end
end
