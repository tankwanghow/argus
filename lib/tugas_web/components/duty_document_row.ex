defmodule TugasWeb.DutyDocumentRow do
  @moduledoc """
  Shared live-document actions, void confirmation, and voided-file rows used by
  completion-document slots and per-step supporting files.
  """
  use Phoenix.Component

  import TugasWeb.CoreComponents

  alias Tugas.Duties

  attr :doc, :map, required: true
  attr :duty, :map, required: true
  attr :current_scope, :map, required: true
  attr :voiding_document_id, :any, default: nil
  attr :deleting_document_id, :any, default: nil
  attr :id_prefix, :string, default: ""
  attr :event_id, :any, default: nil

  def live_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1 shrink-0">
      <%= if @deleting_document_id == @doc.id do %>
        <button
          id={"#{@id_prefix}confirm-delete-doc-#{@doc.id}"}
          type="button"
          phx-click="delete_document"
          phx-value-document_id={@doc.id}
          {event_id_attr(@event_id)}
          phx-disable-with="Deleting…"
          class="text-xl cursor-pointer"
        >
          ✅
        </button>
        <button type="button" phx-click="cancel_delete_document" class="text-xl cursor-pointer">
          ❌
        </button>
      <% else %>
        <button
          :if={
            @voiding_document_id != @doc.id &&
              Duties.document_deletable?(@current_scope, @duty, @doc)
          }
          id={"#{@id_prefix}delete-doc-#{@doc.id}"}
          type="button"
          phx-click="request_delete_document"
          phx-value-document_id={@doc.id}
          {event_id_attr(@event_id)}
          class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
        >
          Delete
        </button>
        <button
          :if={
            cycle_live?(@duty) && @voiding_document_id != @doc.id &&
              Duties.document_voidable?(@current_scope, @duty, @doc)
          }
          id={"#{@id_prefix}void-doc-#{@doc.id}"}
          type="button"
          phx-click="void_document"
          phx-value-document_id={@doc.id}
          class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
        >
          Void
        </button>
      <% end %>
    </div>
    """
  end

  attr :doc, :map, required: true
  attr :void_reason_required?, :boolean, required: true
  attr :id_prefix, :string, required: true
  attr :event_id, :any, default: nil

  def void_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"#{@id_prefix}void-form-#{@doc.id}"}
      phx-submit="confirm_void_document"
      class="mt-2 pl-5 space-y-2"
    >
      <input type="hidden" name="document_id" value={@doc.id} />
      <input :if={@event_id} type="hidden" name="event_id" value={@event_id} />
      <.input
        :if={@void_reason_required?}
        name="reason"
        type="text"
        label="Reason for voiding"
        required
      />
      <div class="flex flex-wrap gap-2">
        <.button class="btn btn-error btn-xs" phx-disable-with="Voiding…">Confirm void</.button>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_void_document">
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  attr :doc, :map, required: true
  attr :entity_slug, :string, required: true
  attr :duty, :map, required: true
  attr :timezone, :string, default: nil
  attr :show_dates?, :boolean, default: true
  attr :id_prefix, :string, default: ""
  attr :show_slot_badge?, :boolean, default: false
  attr :datetime_format, :atom, values: [:default, :short], default: :default

  def voided_row(assigns) do
    ~H"""
    <li id={"#{@id_prefix}voided-doc-#{@doc.id}"} class="px-2.5 py-2 text-sm">
      <div class="flex items-center gap-x-2">
        <.doc_link
          href={"/entities/#{@entity_slug}/duties/#{@duty.id}/documents/#{@doc.id}"}
          name={file_name(@doc)}
          icon_class="size-3.5 text-base-content/40 shrink-0"
          class="link link-hover truncate min-w-0 flex-1 line-through text-base-content/40"
        />
        <span
          :if={@show_slot_badge? && @doc.document_slot}
          class="badge badge-xs badge-ghost shrink-0"
        >
          {@doc.document_slot}
        </span>
        <span class="badge badge-xs badge-error shrink-0">voided</span>
        <span
          :if={@show_dates?}
          class="text-xs text-base-content/50 shrink-0 whitespace-nowrap"
        >
          {format_doc_datetime(@doc.inserted_at, @datetime_format, @timezone)}
        </span>
      </div>
      <p :if={@doc.void_reason} class="text-xs text-base-content/50 mt-1 pl-5">
        Void reason: {@doc.void_reason}
      </p>
    </li>
    """
  end

  @doc false
  def file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end

  defp event_id_attr(nil), do: %{}
  defp event_id_attr(id), do: %{"phx-value-event_id" => to_string(id)}

  defp format_doc_datetime(dt, format, timezone), do: format_datetime(dt, timezone, format)

  defp cycle_live?(%{completed_at: nil, closed_at: nil}), do: true
  defp cycle_live?(_), do: false
end
