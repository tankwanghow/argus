defmodule ArgusWeb.ObligationLive.Form do
  use ArgusWeb, :live_view

  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.Obligation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligation-form">
        <div class="text-2xl font-bold">New obligation</div>

        <.form
          for={@form}
          id="obligation-create-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-1 max-w-xl space-y-4"
        >
          <.char_count_input field={@form[:title]} label="Title" max={30} required />
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:obligation_type_id]}
              type="select"
              label="Type"
              options={@type_options}
              prompt="Choose a type"
              required
            />
            <.input field={@form[:due_by]} type="date" label="Due by" required />
          </div>
          <.input field={@form[:open_note]} type="textarea" label="Open note" required />
          <div class="fieldset">
            <label class="label">Collaborators</label>
            <.input
              field={@form[:primary_assignee_id]}
              type="select"
              label="Primary assignee"
              options={@member_options}
              prompt="Unassigned"
            />
            <label class="label mt-2" for="collaborator-ids">Also collaborating (optional)</label>
            <select
              id="collaborator-ids"
              name="obligation[collaborator_ids][]"
              multiple
              class="select w-full h-32"
            >
              <option :for={{label, id} <- @member_options} value={id}>{label}</option>
            </select>
            <p class="text-xs text-base-content/50 mt-1">
              Hold ⌘/Ctrl to select more than one.
            </p>
          </div>
        </.form>

        <section id="create-document-upload" class="fieldset max-w-xl mt-4">
          <label class="label mb-1">Attachments (optional)</label>
          <p class="text-xs text-base-content/50 mb-2">
            Add supporting files to the opening step. Completion documents can be uploaded after creation.
          </p>
          <form
            id="create-document-form"
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
            id="staged-documents"
            class="mt-3 space-y-1.5 text-sm"
          >
            <li
              :for={entry <- @uploads.document.entries}
              id={"staged-document-#{entry.ref}"}
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
          form="obligation-create-form"
          class="btn btn-primary mt-4"
          phx-disable-with="Creating..."
        >
          Create obligation
        </button>
      </div>
    </Layouts.app>
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
       |> load_form()}
    else
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to create obligations.")
       |> push_navigate(to: ~p"/entities/#{socket.assigns.current_scope.entity.slug}/obligations")}
    end
  end

  @impl true
  def handle_event("validate", %{"obligation" => params}, socket) do
    changeset =
      %Obligation{}
      |> Obligations.change_obligation(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"obligation" => params}, socket) do
    scope = socket.assigns.current_scope

    case Obligations.create_obligation(scope, map_create_params(params)) do
      {:ok, obligation} ->
        socket =
          case attach_uploaded_documents(socket, scope, obligation) do
            :ok ->
              put_flash(socket, :info, "Obligation created.")

            :partial ->
              put_flash(
                socket,
                :error,
                "Obligation created, but some files could not be attached."
              )
          end

        {:noreply,
         push_navigate(socket,
           to: ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "An open note is required.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("validate_create_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_create_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  # Attaches files chosen on the create form to the new obligation's open event.
  # LiveView holds the temp files until consumed here (or garbage-collects them on
  # disconnect), so abandoning the form leaks nothing.
  defp attach_uploaded_documents(socket, scope, obligation) do
    obligation = Obligations.get_obligation!(scope, obligation.id)
    open_event = open_event!(obligation)

    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        upload = %Plug.Upload{
          path: path,
          filename: entry.client_name,
          content_type: entry.client_type
        }

        {:ok, Obligations.add_document(scope, obligation, open_event, upload, nil)}
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)), do: :ok, else: :partial
  end

  defp open_event!(%Obligation{} = obligation) do
    case Enum.find(obligation.events, &(&1.status == "open")) do
      %{} = event -> event
      nil -> raise "open event not found for obligation #{obligation.id}"
    end
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)."
  defp upload_error_to_string(:too_many_files), do: "Too many files selected (max 10)."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(_), do: "Invalid file."

  defp load_form(socket) do
    scope = socket.assigns.current_scope
    changeset = Obligations.change_obligation(%Obligation{})

    socket
    |> assign(:type_options, type_options(scope))
    |> assign(:member_options, member_options(scope))
    |> assign_form(changeset)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "obligation"))
  end

  defp type_options(scope) do
    Enum.map(Obligations.list_types(scope), &{&1.name, &1.id})
  end

  defp member_options(scope) do
    Entities.list_entity_members(scope.entity)
    |> Enum.map(fn {user, _membership} -> {user.email, user.id} end)
  end

  defp map_create_params(params) do
    params
    |> Map.update("due_by", nil, &parse_date/1)
    |> Map.update("primary_assignee_id", nil, &normalize_assignee/1)
    |> Map.take([
      "title",
      "obligation_type_id",
      "primary_assignee_id",
      "due_by",
      "open_note",
      "collaborator_ids"
    ])
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp normalize_assignee(nil), do: nil
  defp normalize_assignee(""), do: nil
  defp normalize_assignee(id), do: id

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
