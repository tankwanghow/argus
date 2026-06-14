defmodule Argus.Uploads do
  @moduledoc """
  Local filesystem storage for obligation event documents.
  """

  def store(%Plug.Upload{} = upload, entity_id, obligation_id) do
    dest_dir = Path.join([base_dir(), to_string(entity_id), to_string(obligation_id)])
    File.mkdir_p!(dest_dir)
    filename = "#{Ecto.UUID.generate()}_#{upload.filename}"
    dest = Path.join(dest_dir, filename)
    File.cp!(upload.path, dest)
    %{filename: filename, original: upload.filename, path: dest}
  end

  @doc """
  Copies an uploaded file into entity staging storage before an obligation exists.
  """
  def stage(%Plug.Upload{} = upload, entity_id) do
    dest_dir = Path.join([base_dir(), to_string(entity_id), "_staging"])
    File.mkdir_p!(dest_dir)
    filename = "#{Ecto.UUID.generate()}_#{upload.filename}"
    dest = Path.join(dest_dir, filename)
    File.cp!(upload.path, dest)
    %{path: dest, original: upload.filename, content_type: upload.content_type}
  end

  def delete_staged(%{path: path}) when is_binary(path), do: File.rm(path)
  def delete_staged(_), do: :ok

  def path(%{file: file}) when is_map(file), do: file_path(file)

  defp base_dir do
    Application.get_env(:argus, :uploads_dir, Path.join(:code.priv_dir(:argus), "uploads"))
  end

  defp file_path(file) do
    Map.get(file, "path") || Map.get(file, :path)
  end
end
