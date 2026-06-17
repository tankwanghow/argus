defmodule ArgusWeb.UploadValidate do
  @moduledoc false

  alias ArgusWeb.LiveUpload

  def assign_picked_upload(socket, params) do
    case {LiveUpload.picker_slot_target(params, socket), LiveUpload.find_new_entry_ref(socket)} do
      {nil, _} ->
        socket

      {_target, nil} ->
        socket

      {target, ref} ->
        socket
        |> LiveUpload.assign_slot_entry(target, ref)
        |> Phoenix.Component.assign(:upload_slot_target, LiveUpload.highlight_slot_target(target))
    end
  end
end
