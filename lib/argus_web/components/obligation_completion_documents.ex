defmodule ArgusWeb.ObligationCompletionDocuments do
  @moduledoc """
  Cycle-level required completion documents: one row per required slot (live file
  inline, or an uploader if missing) plus a voided-required section. All file
  management for required slots lives here; slots are immutable after upload.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias ArgusWeb.ObligationDocumentRow
  alias ArgusWeb.UploadSlotControls

  attr :obligation, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :documents, :list, required: true
  attr :required_slots, :list, required: true
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :deleting_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :show_dates?, :boolean, default: true
  attr :id_prefix, :string, default: ""

  def completion_documents(assigns) do
    {slot_rows, voided} =
      ArgusWeb.ObligationLive.DocumentHelpers.completion_view(
        assigns.documents,
        assigns.required_slots
      )

    assigns =
      assigns
      |> assign(:slot_rows, slot_rows)
      |> assign(:voided, voided)

    ~H"""
    <section id={"#{@id_prefix}completion-docs"} class="space-y-3">
      <div :if={@slot_rows == []} class="text-sm text-base-content/50">
        This obligation type has no required completion documents.
      </div>

      <ul class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={{slot, live} <- @slot_rows}
          id={"#{@id_prefix}completion-slot-#{slot}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex items-center gap-x-2">
            <.icon
              name={if(live, do: "hero-check-circle-mini", else: "hero-x-circle-mini")}
              class={["size-4 shrink-0", if(live, do: "text-success", else: "text-warning")]}
            />
            <span class="font-medium shrink-0 whitespace-nowrap">{slot}</span>

            <.doc_link
              :if={live}
              href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{live.id}"}
              name={ObligationDocumentRow.file_name(live)}
              class="link link-hover truncate min-w-0 flex-1"
            />
            <span
              :if={live && @show_dates?}
              class="text-xs text-base-content/50 shrink-0 whitespace-nowrap"
            >
              {format_datetime(live.inserted_at, @current_scope.entity.timezone, :short)}
            </span>

            <ObligationDocumentRow.live_actions
              :if={live}
              doc={live}
              obligation={@obligation}
              current_scope={@current_scope}
              voiding_document_id={@voiding_document_id}
              deleting_document_id={@deleting_document_id}
              id_prefix={@id_prefix}
            />

            <UploadSlotControls.upload_slot_controls
              :if={is_nil(live) and @uploadable?}
              slot={slot}
              id_prefix={@id_prefix}
              upload_url={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents"}
              obligation_id={@obligation.id}
              completion_slot?={true}
              choose_button_id={"#{@id_prefix}select-slot-#{slot}"}
            />
          </div>

          <ObligationDocumentRow.void_form
            :if={live && @voiding_document_id == live.id}
            doc={live}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />
        </li>
      </ul>

      <p :if={@uploadable? and @slot_rows != []} class="text-xs text-base-content/50">
        {Argus.Uploads.Limits.summary()}
      </p>

      <section :if={@voided != []} id={"#{@id_prefix}completion-voided"} class="space-y-1">
        <div class="argus-meta-label">Voided required files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <ObligationDocumentRow.voided_row
            :for={doc <- @voided}
            doc={doc}
            entity_slug={@entity_slug}
            obligation={@obligation}
            timezone={@current_scope.entity.timezone}
            show_dates?={@show_dates?}
            id_prefix={@id_prefix}
            show_slot_badge?={true}
          />
        </ul>
      </section>
    </section>
    """
  end
end
