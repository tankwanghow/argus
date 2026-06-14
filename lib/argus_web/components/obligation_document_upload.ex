defmodule ArgusWeb.ObligationDocumentUpload do
  @moduledoc """
  Per-slot document upload controls for obligation event modals.

  Phoenix allows one `live_file_input` per upload config, so each required slot
  gets its own upload button that activates a shared file picker.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  attr :event, :map, required: true
  attr :required_docs, :list, required: true
  attr :uploads, :map, required: true
  attr :uploadable?, :boolean, required: true
  attr :upload_slot_target, :any, default: nil
  attr :id_prefix, :string, default: ""

  def obligation_document_upload_forms(assigns) do
    ~H"""
    <section :if={@uploadable?} class="mt-6 border-t border-base-300 pt-4 space-y-5">
      <section :if={@required_docs != []} class="space-y-3">
        <h4 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
          Required for completion
        </h4>
        <p class="text-xs text-base-content/50">
          Choose a required slot, then pick a file. Each slot needs one non-voided upload to mark done.
        </p>
        <div class="space-y-2">
          <div
            :for={{slot, satisfied?} <- @required_docs}
            id={"#{@id_prefix}slot-upload-#{@event.id}-#{slot}"}
            class={[
              "rounded-lg border p-3 flex items-center justify-between gap-3",
              upload_target?(@upload_slot_target, slot) && "border-primary bg-primary/5",
              !upload_target?(@upload_slot_target, slot) && "border-base-300"
            ]}
          >
            <div class="flex items-center gap-2 min-w-0">
              <.icon
                name={if satisfied?, do: "hero-check-circle-mini", else: "hero-x-circle-mini"}
                class={[
                  "size-4 shrink-0",
                  if(satisfied?, do: "text-success", else: "text-base-content/40")
                ]}
              />
              <span class="font-medium text-sm">{slot}</span>
              <span :if={satisfied?} class="badge badge-success badge-xs badge-soft">
                Uploaded
              </span>
            </div>
            <button
              :if={not satisfied?}
              id={"#{@id_prefix}select-slot-#{@event.id}-#{slot}"}
              type="button"
              phx-click="select_upload_slot"
              phx-value-event_id={@event.id}
              phx-value-slot={slot}
              class={[
                "btn btn-sm shrink-0",
                upload_target?(@upload_slot_target, slot) && "btn-primary",
                !upload_target?(@upload_slot_target, slot) && "btn-outline"
              ]}
            >
              Upload {slot}
            </button>
            <span :if={satisfied?} class="text-xs text-base-content/50 shrink-0">
              Void below to replace
            </span>
          </div>
        </div>
      </section>

      <section :if={@required_docs != []} class="space-y-2">
        <button
          id={"#{@id_prefix}select-additional-#{@event.id}"}
          type="button"
          phx-click="select_upload_slot"
          phx-value-event_id={@event.id}
          phx-value-slot="additional"
          class={[
            "btn btn-sm btn-outline w-full",
            @upload_slot_target == :additional && "btn-active"
          ]}
        >
          Upload additional file
        </button>
      </section>

      <section :if={@required_docs == []} class="space-y-2">
        <button
          id={"#{@id_prefix}select-upload-#{@event.id}"}
          type="button"
          phx-click="select_upload_slot"
          phx-value-event_id={@event.id}
          phx-value-slot="additional"
          class="btn btn-sm btn-outline w-full"
        >
          Choose file to upload
        </button>
      </section>

      <section
        :if={@upload_slot_target}
        class="rounded-lg border border-primary/30 bg-base-200/40 p-3 space-y-3"
      >
        <div class="flex items-center justify-between gap-2">
          <p class="text-sm font-medium">
            {upload_target_label(@upload_slot_target)}
          </p>
          <button
            type="button"
            phx-click="clear_upload_slot"
            class="btn btn-ghost btn-xs"
          >
            Cancel
          </button>
        </div>
        <.form
          for={%{}}
          id={active_form_id(assigns)}
          phx-change="validate_upload"
          phx-submit="add_document"
          class="space-y-2"
        >
          <input type="hidden" name="event_id" value={@event.id} />
          <input
            :if={is_binary(@upload_slot_target)}
            type="hidden"
            name="document_slot"
            value={@upload_slot_target}
          />
          <.live_file_input upload={@uploads.document} class="file-input w-full" />
          <.button class="btn btn-primary btn-sm w-full" phx-disable-with="Uploading…">
            {upload_button_label(@upload_slot_target)}
          </.button>
        </.form>
      </section>

      <p :for={err <- @uploads.document.errors} class="text-sm text-error">
        {upload_error_to_string(err)}
      </p>
    </section>
    """
  end

  defp upload_target?(target, slot) when is_binary(target), do: target == slot
  defp upload_target?(_, _), do: false

  defp upload_target_label(:additional), do: "Additional file"
  defp upload_target_label(slot) when is_binary(slot), do: "Required slot: #{slot}"

  defp upload_button_label(:additional), do: "Upload file"
  defp upload_button_label(slot) when is_binary(slot), do: "Upload #{slot}"

  defp active_form_id(%{id_prefix: prefix, event: event}) do
    "#{prefix}document-form-#{event.id}-active"
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)."
  defp upload_error_to_string(:too_many_files), do: "You can only upload one file at a time."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(_), do: "Invalid file."
end
