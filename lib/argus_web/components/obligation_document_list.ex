defmodule ArgusWeb.ObligationDocumentList do
  @moduledoc """
  Compact uploaded-document rows for obligation event modals.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  attr :documents, :list, required: true
  attr :event_id, :string, required: true
  attr :obligation_id, :string, required: true
  attr :entity_slug, :string, required: true
  attr :current_scope, :map, required: true
  attr :obligation, :map, required: true
  attr :voiding_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :id_prefix, :string, default: ""
  attr :list_id, :string, required: true

  def obligation_document_list(assigns) do
    ~H"""
    <section class="space-y-2">
      <div class="argus-meta-label">On this step</div>
      <p :if={@documents == []} class="text-sm text-base-content/50">
        No files uploaded here yet.
      </p>
      <ul
        :if={@documents != []}
        id={@list_id}
        class="divide-y divide-base-300 rounded-box border border-base-300"
      >
        <li
          :for={doc <- @documents}
          id={"#{@id_prefix}doc-row-#{doc.id}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/40 shrink-0" />
            <.link
              href={"/entities/#{@entity_slug}/obligations/#{@obligation_id}/documents/#{doc.id}"}
              target="_blank"
              class={[
                "link link-hover truncate max-w-[14rem]",
                doc.voided_at && "line-through text-base-content/40"
              ]}
            >
              {file_name(doc)}
            </.link>
            <span :if={doc.document_slot} class="badge badge-xs badge-ghost">{doc.document_slot}</span>
            <span :if={doc.voided_at} class="badge badge-xs badge-error">voided</span>
            <span class="text-xs text-base-content/50">{format_datetime(doc.inserted_at)}</span>
            <button
              :if={
                @voiding_document_id != doc.id and
                  Argus.Obligations.document_voidable?(@current_scope, @obligation, doc)
              }
              id={"#{@id_prefix}void-doc-#{doc.id}"}
              type="button"
              phx-click="void_document"
              phx-value-document_id={doc.id}
              class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error ml-auto"
            >
              Void
            </button>
          </div>
          <p :if={doc.void_reason} class="text-xs text-base-content/50 mt-1 pl-5">
            Void reason: {doc.void_reason}
          </p>
          <.form
            :if={@voiding_document_id == doc.id}
            for={%{}}
            id={"#{@id_prefix}void-form-#{doc.id}"}
            phx-submit="confirm_void_document"
            class="mt-2 pl-5 space-y-2"
          >
            <input type="hidden" name="document_id" value={doc.id} />
            <input type="hidden" name="event_id" value={@event_id} />
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
        </li>
      </ul>
    </section>
    """
  end

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end
end
