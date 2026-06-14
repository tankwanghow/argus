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
  attr :create_mode?, :boolean, default: false

  def obligation_document_upload_forms(assigns) do
    ~H"""
    <section
      :if={@uploadable?}
      id={"#{@id_prefix}document-upload-panel-#{@event.id}"}
      class="space-y-2"
    >
      <div :if={@required_docs != []} class="space-y-1">
        <div class="argus-meta-label">Completion documents</div>
        <p class="text-xs text-base-content/50">
          Needed to mark done — upload anytime while this cycle is open.
        </p>
      </div>

      <div :if={@required_docs != []} class="space-y-1.5">
        <div
          :for={{slot, satisfied?} <- @required_docs}
          id={"#{@id_prefix}slot-upload-#{@event.id}-#{slot}"}
          class={[
            "rounded-box border p-2.5",
            upload_target?(@upload_slot_target, slot) && "border-primary bg-primary/5",
            !upload_target?(@upload_slot_target, slot) && "border-base-300"
          ]}
        >
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <.icon
              name={if satisfied?, do: "hero-check-circle-mini", else: "hero-x-circle-mini"}
              class={[
                "size-4 shrink-0",
                if(satisfied?, do: "text-success", else: "text-warning")
              ]}
            />
            <span class="font-medium text-sm">{slot}</span>
            <span :if={satisfied?} class="badge badge-success badge-xs badge-soft">Uploaded</span>
            <span :if={not satisfied?} class="badge badge-ghost badge-xs badge-soft">Not uploaded</span>
            <button
              :if={not satisfied? and not upload_target?(@upload_slot_target, slot)}
              id={"#{@id_prefix}select-slot-#{@event.id}-#{slot}"}
              type="button"
              phx-click={select_slot_event(@create_mode?)}
              phx-value-event_id={@event.id}
              phx-value-slot={slot}
              class="btn btn-primary btn-xs h-7 min-h-7 ml-auto"
            >
              Choose file
            </button>
            <span :if={satisfied?} class="text-xs text-base-content/50 ml-auto">
              Void below to replace
            </span>
          </div>
          <.upload_form
            :if={upload_target?(@upload_slot_target, slot)}
            event={@event}
            uploads={@uploads}
            upload_slot_target={slot}
            id_prefix={@id_prefix}
            create_mode?={@create_mode?}
          />
        </div>
      </div>

      <div
        :if={@required_docs != []}
        id={"#{@id_prefix}additional-upload-#{@event.id}"}
        class={[
          "rounded-box border p-2.5",
          @upload_slot_target == :additional && "border-primary bg-primary/5",
          @upload_slot_target != :additional && "border-base-300 border-dashed"
        ]}
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-sm text-base-content/70">Additional file</span>
          <button
            :if={@upload_slot_target != :additional}
            id={"#{@id_prefix}select-additional-#{@event.id}"}
            type="button"
            phx-click={select_slot_event(@create_mode?)}
            phx-value-event_id={@event.id}
            phx-value-slot="additional"
            class="btn btn-outline btn-xs h-7 min-h-7 ml-auto"
          >
            Choose file
          </button>
        </div>
        <.upload_form
          :if={@upload_slot_target == :additional}
          event={@event}
          uploads={@uploads}
          upload_slot_target={:additional}
          id_prefix={@id_prefix}
          create_mode?={@create_mode?}
        />
      </div>

      <div
        :if={@required_docs == []}
        id={"#{@id_prefix}slot-upload-#{@event.id}-any"}
        class={[
          "rounded-box border p-2.5",
          @upload_slot_target == :additional && "border-primary bg-primary/5",
          @upload_slot_target != :additional && "border-base-300"
        ]}
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-sm font-medium">Attach a file</span>
          <button
            :if={@upload_slot_target != :additional}
            id={"#{@id_prefix}select-upload-#{@event.id}"}
            type="button"
            phx-click={select_slot_event(@create_mode?)}
            phx-value-event_id={@event.id}
            phx-value-slot="additional"
            class="btn btn-primary btn-xs h-7 min-h-7 ml-auto"
          >
            Choose file
          </button>
        </div>
        <.upload_form
          :if={@upload_slot_target == :additional}
          event={@event}
          uploads={@uploads}
          upload_slot_target={:additional}
          id_prefix={@id_prefix}
          create_mode?={@create_mode?}
        />
      </div>

      <p :for={err <- @uploads.document.errors} class="text-sm text-error">
        {upload_error_to_string(err)}
      </p>
    </section>
    """
  end

  attr :event, :map, required: true
  attr :uploads, :map, required: true
  attr :upload_slot_target, :any, required: true
  attr :id_prefix, :string, default: ""
  attr :create_mode?, :boolean, default: false

  defp upload_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={active_form_id(assigns)}
      phx-change={upload_validate_event(@create_mode?)}
      phx-submit={upload_submit_event(@create_mode?)}
      class="mt-2 pt-2 border-t border-base-300/80 space-y-2"
    >
      <input :if={not @create_mode?} type="hidden" name="event_id" value={@event.id} />
      <input
        :if={is_binary(@upload_slot_target)}
        type="hidden"
        name="document_slot"
        value={@upload_slot_target}
      />
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
        <.live_file_input upload={@uploads.document} class="file-input file-input-sm w-full flex-1" />
        <.button class="btn btn-primary btn-sm shrink-0" phx-disable-with="Uploading…">
          {upload_button_label(@upload_slot_target)}
        </.button>
        <button
          type="button"
          phx-click={clear_slot_event(@create_mode?)}
          class="btn btn-ghost btn-xs shrink-0"
        >
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  defp upload_target?(target, slot) when is_binary(target), do: target == slot
  defp upload_target?(_, _), do: false

  defp upload_button_label(:additional), do: "Upload"
  defp upload_button_label(slot) when is_binary(slot), do: "Upload #{slot}"

  defp active_form_id(%{id_prefix: prefix, event: event}) do
    "#{prefix}document-form-#{event.id}-active"
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)."
  defp upload_error_to_string(:too_many_files), do: "You can only upload one file at a time."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(_), do: "Invalid file."

  defp select_slot_event(true), do: "select_create_upload_slot"
  defp select_slot_event(false), do: "select_upload_slot"

  defp clear_slot_event(true), do: "clear_create_upload_slot"
  defp clear_slot_event(false), do: "clear_upload_slot"

  defp upload_validate_event(true), do: "validate_create_upload"
  defp upload_validate_event(false), do: "validate_upload"

  defp upload_submit_event(true), do: "stage_create_document"
  defp upload_submit_event(false), do: "add_document"
end
