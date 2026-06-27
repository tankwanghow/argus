defmodule TugasWeb.DutyStepFiles do
  @moduledoc """
  Per-step supporting (non-required) files: this event's live "other" files and a
  voided-other area, plus an additional-file uploader when the step is uploadable.
  """
  use Phoenix.Component

  import TugasWeb.CoreComponents

  alias TugasWeb.DutyDocumentRow
  alias TugasWeb.UploadSlotControls

  attr :event, :map, required: true
  attr :duty, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :required_slots, :list, required: true
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :deleting_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :show_dates?, :boolean, default: true
  attr :id_prefix, :string, default: ""

  def step_files(assigns) do
    {live_other, voided_other} =
      TugasWeb.DutyLive.DocumentHelpers.step_files(
        assigns.event.documents,
        assigns.required_slots
      )

    assigns =
      assigns
      |> assign(:live_other, live_other)
      |> assign(:voided_other, voided_other)

    ~H"""
    <section id={"#{@id_prefix}step-files-#{@event.id}"} class="space-y-3">
      <div class="tugas-meta-label">Supporting files</div>

      <p :if={@live_other == []} class="text-sm text-base-content/50">
        No supporting files on this step.
      </p>
      <ul :if={@live_other != []} class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={doc <- @live_other}
          id={"#{@id_prefix}doc-row-#{doc.id}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex items-center gap-2">
            <.doc_link
              href={"/entities/#{@entity_slug}/duties/#{@duty.id}/documents/#{doc.id}"}
              name={DutyDocumentRow.file_name(doc)}
              class="link link-hover truncate min-w-0 flex-1"
            />
            <span
              :if={@show_dates?}
              class="text-xs text-base-content/50 shrink-0 whitespace-nowrap"
            >
              {format_datetime(doc.inserted_at, @current_scope.entity.timezone)}
            </span>
            <DutyDocumentRow.live_actions
              doc={doc}
              duty={@duty}
              current_scope={@current_scope}
              voiding_document_id={@voiding_document_id}
              deleting_document_id={@deleting_document_id}
              id_prefix={@id_prefix}
              event_id={@event.id}
            />
          </div>
          <DutyDocumentRow.void_form
            :if={@voiding_document_id == doc.id}
            doc={doc}
            event_id={@event.id}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />
        </li>
      </ul>

      <div :if={@uploadable?} class="rounded-box border border-dashed border-base-300 p-2.5">
        <UploadSlotControls.upload_slot_controls
          slot="additional"
          id_prefix={@id_prefix}
          upload_url={"/entities/#{@entity_slug}/duties/#{@duty.id}/documents"}
          duty_id={@duty.id}
          event_id={to_string(@event.id)}
          idle_label="Additional file"
          choose_button_id={"#{@id_prefix}select-additional-#{@event.id}"}
          choose_button_class="btn btn-outline btn-xs h-7 min-h-7 ml-auto"
        />
        <p class="mt-1 text-xs text-base-content/50">{Tugas.Uploads.Limits.summary()}</p>
      </div>

      <section
        :if={@voided_other != []}
        id={"#{@id_prefix}step-voided-#{@event.id}"}
        class="space-y-1"
      >
        <div class="tugas-meta-label">Voided files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <DutyDocumentRow.voided_row
            :for={doc <- @voided_other}
            doc={doc}
            entity_slug={@entity_slug}
            duty={@duty}
            timezone={@current_scope.entity.timezone}
            show_dates?={@show_dates?}
            id_prefix={@id_prefix}
          />
        </ul>
      </section>
    </section>
    """
  end
end
