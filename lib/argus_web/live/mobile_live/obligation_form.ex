defmodule ArgusWeb.MobileLive.ObligationForm do
  @moduledoc """
  Mobile new-obligation form. Mirrors `ObligationLive.Form` but renders in the
  `Layouts.mobile_app` bottom-nav shell; all logic is shared via
  `ArgusWeb.ObligationLive.CreateForm`.
  """
  use ArgusWeb, :live_view

  import ArgusWeb.ObligationLive.CreateForm, only: [upload_error_to_string: 1]

  alias ArgusWeb.ObligationLive.CreateForm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:obligations}>
      <div id="m-obligation-form" class="space-y-3">
        <.link
          navigate={~p"/m/#{@current_scope.entity.slug}/obligations"}
          class="text-sm text-base-content/60 flex items-center gap-1"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" /> Obligations
        </.link>
        <h1 class="text-lg font-semibold">New obligation</h1>

        <.form
          for={@form}
          id="m-obligation-create-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.char_count_input field={@form[:title]} label="Title" max={30} required />
          <.input
            field={@form[:obligation_type_id]}
            type="select"
            label="Type"
            options={@type_options}
            prompt="Choose a type"
            required
          />
          <.input field={@form[:due_by]} type="date" label="Due by" required />
          <.input field={@form[:open_note]} type="textarea" label="Open note" required />
          <.input
            field={@form[:primary_assignee_id]}
            type="select"
            label="Primary assignee"
            options={@member_options}
            prompt="Unassigned"
          />
          <div class="fieldset">
            <label class="label" for="m-collaborator-ids">Also collaborating (optional)</label>
            <select
              id="m-collaborator-ids"
              name="obligation[collaborator_ids][]"
              multiple
              class="select w-full h-32"
            >
              <option :for={{label, id} <- @member_options} value={id}>{label}</option>
            </select>
          </div>
        </.form>

        <section id="m-create-document-upload" class="fieldset">
          <label class="label mb-1">Attachments (optional)</label>
          <p class="text-xs text-base-content/50 mb-2">
            Add supporting files to the opening step. Completion documents can be uploaded after creation.
          </p>
          <form
            id="m-create-document-form"
            phx-change="validate_create_upload"
            phx-submit="validate_create_upload"
          >
            <label class="btn btn-primary btn-sm cursor-pointer">
              <.icon name="hero-paper-clip-mini" class="size-4" /> Choose files
              <.live_file_input upload={@uploads.document} class="sr-only" />
            </label>
          </form>

          <ul
            :if={@uploads.document.entries != []}
            id="m-staged-documents"
            class="mt-3 space-y-1.5 text-sm"
          >
            <li
              :for={entry <- @uploads.document.entries}
              id={"m-staged-document-#{entry.ref}"}
              class="flex flex-wrap items-center gap-2 rounded-box border border-base-300 px-2.5 py-1.5"
            >
              <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/50" />
              <span class="font-medium truncate min-w-0 flex-1">{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel_create_upload"
                phx-value-ref={entry.ref}
                class="btn btn-ghost btn-xs ml-auto"
              >
                Remove
              </button>
              <p
                :for={err <- upload_errors(@uploads.document, entry)}
                class="basis-full text-xs text-error"
              >
                {upload_error_to_string(err)}
              </p>
            </li>
          </ul>
          <p :for={err <- upload_errors(@uploads.document)} class="text-xs text-error mt-1">
            {upload_error_to_string(err)}
          </p>
        </section>

        <button
          type="submit"
          form="m-obligation-create-form"
          class="btn btn-primary w-full"
          phx-disable-with="Creating..."
        >
          Create obligation
        </button>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Argus.Authorization.can?(socket.assigns.current_scope, :create_obligation) do
      {:ok,
       socket
       |> allow_upload(:document,
         accept: :any,
         max_entries: ArgusWeb.LiveUpload.max_document_entries(),
         max_file_size: 20_000_000,
         auto_upload: true
       )
       |> CreateForm.load_form()}
    else
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to create obligations.")
       |> push_navigate(to: ~p"/m/#{socket.assigns.current_scope.entity.slug}/obligations")}
    end
  end

  @impl true
  def handle_event("validate", %{"obligation" => params}, socket) do
    CreateForm.validate(socket, params)
  end

  def handle_event("save", %{"obligation" => params}, socket) do
    CreateForm.save(socket, params, fn scope, obligation ->
      ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}"
    end)
  end

  def handle_event("validate_create_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_create_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end
end
