defmodule ArgusWeb.LiveUpload do
  @moduledoc false

  import Phoenix.LiveView, only: [cancel_upload: 3, consume_uploaded_entry: 3]

  @max_document_entries 10
  @max_document_file_size 20_000_000

  def max_document_entries, do: @max_document_entries
  def max_document_file_size, do: @max_document_file_size

  @doc """
  Human-readable messages for an upload entry's errors (e.g. an oversized file).
  Returns `[]` when there is no entry or no error.
  """
  def entry_error_messages(uploads, entry) do
    uploads
    |> entry_errors(entry)
    |> Enum.map(&error_message/1)
  end

  defp entry_errors(%{document: conf}, %{} = entry),
    do: Phoenix.Component.upload_errors(conf, entry)

  defp entry_errors(_uploads, _entry), do: []

  defp error_message(:too_large),
    do: "File is too large (max #{div(@max_document_file_size, 1_000_000)} MB)."

  defp error_message(:not_accepted), do: "This file type is not allowed."
  defp error_message(:too_many_files), do: "Too many files selected."
  defp error_message(:external_client_failure), do: "Upload failed. Please try again."
  defp error_message(_other), do: "This file can't be uploaded."

  def slot_key("additional"), do: "additional"
  def slot_key(:additional), do: "additional"
  def slot_key(slot) when is_binary(slot), do: slot

  def entry_for_slot(uploads, entries_map, slot) do
    case Map.get(entries_map || %{}, slot_key(slot)) do
      nil ->
        nil

      ref ->
        uploads
        |> upload_entries()
        |> Enum.find(&(&1.ref == ref))
    end
  end

  def assign_slot_entry(socket, slot, ref) do
    socket = clear_slot_entry(socket, slot)
    entries_map = socket.assigns[:upload_slot_entries] || %{}

    Phoenix.Component.assign(
      socket,
      :upload_slot_entries,
      Map.put(entries_map, slot_key(slot), ref)
    )
  end

  def picker_slot_target(params, socket) do
    case Map.get(params, "picker_slot") do
      "additional" -> :additional
      slot when is_binary(slot) and slot != "" -> slot
      _ -> socket.assigns[:upload_slot_target]
    end
  end

  def highlight_slot_target(:additional), do: :additional
  def highlight_slot_target(slot) when is_binary(slot), do: slot
  def highlight_slot_target(_), do: nil

  def clear_slot_entry(socket, slot) do
    entries_map = socket.assigns[:upload_slot_entries] || %{}

    socket =
      case Map.get(entries_map, slot_key(slot)) do
        nil ->
          socket

        ref ->
          cancel_pending_upload(socket, ref)
      end

    Phoenix.Component.assign(
      socket,
      :upload_slot_entries,
      Map.delete(entries_map, slot_key(slot))
    )
  end

  def clear_all_slot_entries(socket) do
    entries_map = socket.assigns[:upload_slot_entries] || %{}

    socket =
      Enum.reduce(entries_map, socket, fn {_slot, ref}, acc ->
        cancel_pending_upload(acc, ref)
      end)

    Phoenix.Component.assign(socket, :upload_slot_entries, %{})
  end

  defp cancel_pending_upload(socket, ref) do
    if entry_still_pending?(socket, ref) do
      try do
        cancel_upload(socket, :document, ref)
      catch
        :exit, _ -> socket
      end
    else
      socket
    end
  end

  defp entry_still_pending?(socket, ref) do
    Enum.any?(upload_entries(socket.assigns[:uploads] || %{}), &(&1.ref == ref))
  end

  def find_new_entry_ref(socket) do
    entries = upload_entries(socket.assigns[:uploads] || %{})
    entries_map = socket.assigns[:upload_slot_entries] || %{}
    mapped_refs = entries_map |> Map.values() |> MapSet.new()

    Enum.find_value(entries, fn entry ->
      if MapSet.member?(mapped_refs, entry.ref), do: nil, else: entry.ref
    end)
  end

  def entry_ready?(nil), do: false
  def entry_ready?(%{done?: true}), do: true
  def entry_ready?(_), do: false

  def consume_slot_entry(socket, ref, func) when is_function(func, 2) do
    case Enum.find(upload_entries(socket.assigns[:uploads] || %{}), &(&1.ref == ref)) do
      nil ->
        {:error, :no_entry}

      %{done?: false} ->
        {:error, :not_ready}

      entry ->
        consume_uploaded_entry(socket, entry, fn meta -> func.(meta, entry) end)
    end
  end

  def upload_entries(%{document: %{entries: entries}}) when is_list(entries), do: entries
  def upload_entries(_), do: []
end
