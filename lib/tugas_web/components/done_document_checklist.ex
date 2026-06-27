defmodule TugasWeb.DoneDocumentChecklist do
  @moduledoc """
  Read-only required-document checklist for the Mark Done modal.
  """
  use Phoenix.Component

  import TugasWeb.CoreComponents, only: [icon: 1]

  attr :required_docs, :list, required: true
  attr :id, :string, default: "done-document-checklist"
  attr :upload_btn_id, :string, default: "done-doc-upload-now"
  attr :can_upload?, :boolean, default: false

  def done_document_checklist(assigns) do
    assigns =
      assign(assigns, :missing?, Enum.any?(assigns.required_docs, fn {_, ok?} -> !ok? end))

    ~H"""
    <section
      :if={@required_docs != []}
      id={@id}
      class="rounded-box border border-base-300 bg-base-200/40 p-3 space-y-2"
    >
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
        Required documents
      </div>
      <ul class="space-y-1">
        <li
          :for={{slot, satisfied?} <- @required_docs}
          id={"#{@id}-#{slot}"}
          class="flex items-center gap-2 text-sm"
        >
          <.icon
            name={if satisfied?, do: "hero-check-circle-mini", else: "hero-x-circle-mini"}
            class={["size-4 shrink-0", if(satisfied?, do: "text-success", else: "text-warning")]}
          />
          <span class={if satisfied?, do: "", else: "text-base-content/80"}>{slot}</span>
          <span :if={satisfied?} class="text-xs text-success">Uploaded</span>
          <span :if={!satisfied?} class="text-xs text-warning">Missing</span>
        </li>
      </ul>
      <p :if={@missing? and @can_upload?} class="text-xs text-base-content/60">
        Attach files on the timeline, or <button
          :if={@can_upload?}
          id={@upload_btn_id}
          type="button"
          phx-click="open_documents_from_done"
          class="link link-primary"
        >
          upload now
        </button>.
      </p>
      <p :if={not @missing?} class="text-xs text-success">
        All required documents are uploaded.
      </p>
    </section>
    """
  end
end
