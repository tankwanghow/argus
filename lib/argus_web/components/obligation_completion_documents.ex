defmodule ArgusWeb.ObligationCompletionDocuments do
  @moduledoc """
  Cycle-level required completion documents: one row per required slot (live file
  inline, or an uploader if missing) plus a voided-required section. All file
  management for required slots lives here; slots are immutable after upload.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias Argus.Obligations
  alias ArgusWeb.LiveUpload

  attr :obligation, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :documents, :list, required: true
  attr :required_slots, :list, required: true
  attr :uploads, :map, required: true
  attr :upload_slot_target, :any, default: nil
  attr :upload_slot_entries, :map, default: %{}
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
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
      |> assign(:form_id, "#{assigns.id_prefix}completion-upload-form")

    ~H"""
    <section id={"#{@id_prefix}completion-docs"} class="space-y-3">
      <div :if={@slot_rows == []} class="text-sm text-base-content/50">
        This obligation type has no required completion documents.
      </div>

      <div class="argus-meta-label">Completion documents</div>

      <ul class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={{slot, live} <- @slot_rows}
          id={"#{@id_prefix}completion-slot-#{slot}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <.icon
              name={if(live, do: "hero-check-circle-mini", else: "hero-x-circle-mini")}
              class={["size-4 shrink-0", if(live, do: "text-success", else: "text-warning")]}
            />
            <span class="font-medium">{slot}</span>

            <.link
              :if={live}
              href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{live.id}"}
              target="_blank"
              class="link link-hover truncate max-w-[12rem]"
            >
              {file_name(live)}
            </.link>
            <span :if={live} class="text-xs text-base-content/50">
              {format_datetime(live.inserted_at)}
            </span>

            <span :if={is_nil(live)} class="badge badge-ghost badge-xs badge-soft">Not uploaded</span>

            <div class="ml-auto flex items-center gap-1">
              <button
                :if={live && Obligations.document_deletable?(@current_scope, @obligation, live)}
                id={"#{@id_prefix}delete-doc-#{live.id}"}
                type="button"
                phx-click="delete_document"
                phx-value-document_id={live.id}
                class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
              >
                Delete
              </button>
              <button
                :if={
                  live && @voiding_document_id != live.id &&
                    Obligations.document_voidable?(@current_scope, @obligation, live)
                }
                id={"#{@id_prefix}void-doc-#{live.id}"}
                type="button"
                phx-click="void_document"
                phx-value-document_id={live.id}
                class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
              >
                Void
              </button>
            </div>
          </div>

          <.void_form
            :if={live && @voiding_document_id == live.id}
            doc={live}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />

          <.slot_uploader
            :if={is_nil(live) and @uploadable?}
            slot={slot}
            id_prefix={@id_prefix}
            pending_entry={LiveUpload.entry_for_slot(@uploads, @upload_slot_entries, slot)}
          />
        </li>
      </ul>

      <section :if={@voided != []} id={"#{@id_prefix}completion-voided"} class="space-y-1">
        <div class="argus-meta-label">Voided required files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={doc <- @voided}
            id={"#{@id_prefix}voided-doc-#{doc.id}"}
            class="px-2.5 py-2 text-sm"
          >
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/40 shrink-0" />
              <.link
                href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{doc.id}"}
                target="_blank"
                class="link link-hover truncate max-w-[12rem] line-through text-base-content/40"
              >
                {file_name(doc)}
              </.link>
              <span :if={doc.document_slot} class="badge badge-xs badge-ghost">{doc.document_slot}</span>
              <span class="badge badge-xs badge-error">voided</span>
              <span class="text-xs text-base-content/50">{format_datetime(doc.inserted_at)}</span>
            </div>
            <p :if={doc.void_reason} class="text-xs text-base-content/50 mt-1 pl-5">
              Void reason: {doc.void_reason}
            </p>
          </li>
        </ul>
      </section>

      <.upload_form
        :if={@uploadable?}
        form_id={@form_id}
        uploads={@uploads}
        upload_slot_target={@upload_slot_target}
        id_prefix={@id_prefix}
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SlotFilePicker">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const panel = this.el.closest("section")
              const form = panel?.querySelector("[data-upload-form]")
              if (!form) return
              const slot = this.el.dataset.slot
              const pickerInput = form.querySelector("[name='picker_slot']")
              const slotInput = form.querySelector("[name='document_slot']")
              if (pickerInput) pickerInput.value = slot
              if (slotInput) { slotInput.disabled = false; slotInput.value = slot }
              const fileInput = form.querySelector("input[type='file']")
              if (fileInput) fileInput.click()
            })
          }
        }
      </script>
    </section>
    """
  end

  attr :slot, :string, required: true
  attr :id_prefix, :string, required: true
  attr :pending_entry, :any, default: nil

  defp slot_uploader(assigns) do
    assigns = assign(assigns, :ready?, LiveUpload.entry_ready?(assigns.pending_entry))

    ~H"""
    <div class="mt-2 flex flex-wrap items-center gap-2 border-t border-base-300/80 pt-2">
      <%= if @pending_entry do %>
        <span class="text-sm font-medium truncate min-w-0 flex-1">{@pending_entry.client_name}</span>
        <button
          id={"#{@id_prefix}upload-slot-#{@slot}"}
          type="button"
          phx-click="add_document"
          phx-value-slot={@slot}
          disabled={not @ready?}
          class={["btn btn-primary btn-xs h-7 min-h-7 shrink-0", not @ready? && "btn-disabled"]}
          phx-disable-with="Saving…"
        >
          Upload {@slot}
        </button>
        <button
          type="button"
          phx-click="clear_upload_slot"
          phx-value-slot={@slot}
          class="btn btn-ghost btn-xs h-7 min-h-7 shrink-0"
        >
          Cancel
        </button>
      <% else %>
        <button
          id={"#{@id_prefix}select-slot-#{@slot}"}
          type="button"
          phx-hook=".SlotFilePicker"
          data-slot={@slot}
          phx-click="select_upload_slot"
          phx-value-slot={@slot}
          class="btn btn-primary btn-xs h-7 min-h-7 ml-auto"
        >
          Choose file
        </button>
      <% end %>
    </div>
    """
  end

  attr :form_id, :string, required: true
  attr :uploads, :map, required: true
  attr :upload_slot_target, :any, default: nil
  attr :id_prefix, :string, required: true

  defp upload_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={@form_id}
      data-upload-form
      phx-change="validate_upload"
      phx-submit="add_document"
      class="sr-only"
    >
      <input type="hidden" name="picker_slot" value={picker_value(@upload_slot_target)} />
      <input
        type="hidden"
        name="document_slot"
        value={slot_value(@upload_slot_target)}
        disabled={@upload_slot_target in [nil, :additional]}
      />
      <.live_file_input upload={@uploads.document} class="sr-only" />
    </.form>
    """
  end

  attr :doc, :map, required: true
  attr :void_reason_required?, :boolean, required: true
  attr :id_prefix, :string, required: true

  defp void_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"#{@id_prefix}void-form-#{@doc.id}"}
      phx-submit="confirm_void_document"
      class="mt-2 pl-5 space-y-2"
    >
      <input type="hidden" name="document_id" value={@doc.id} />
      <.input
        :if={@void_reason_required?}
        name="reason"
        type="text"
        label="Reason for voiding"
        required
      />
      <div class="flex flex-wrap gap-2">
        <.button class="btn btn-error btn-xs" phx-disable-with="Voiding…">Confirm void</.button>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_void_document">Cancel</button>
      </div>
    </.form>
    """
  end

  defp picker_value(slot) when is_binary(slot), do: slot
  defp picker_value(_), do: ""
  defp slot_value(slot) when is_binary(slot), do: slot
  defp slot_value(_), do: ""

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end
end
