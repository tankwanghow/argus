defmodule ArgusWeb.ObligationLive.Form do
  use ArgusWeb, :live_view

  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.Obligation
  alias Argus.Uploads

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
          <.input field={@form[:title]} type="text" label="Title" required />
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
          <.obligation_document_upload_forms
            event={%{id: "new"}}
            required_docs={[]}
            uploads={@uploads}
            uploadable?={true}
            upload_slot_target={@upload_slot_target}
            id_prefix="create-"
            create_mode?={true}
          />
          <ul
            :if={@staged_documents != []}
            id="staged-documents"
            class="mt-3 space-y-1.5 text-sm"
          >
            <li
              :for={doc <- @staged_documents}
              id={"staged-document-#{doc.ref}"}
              class="flex flex-wrap items-center gap-2 rounded-box border border-base-300 px-2.5 py-1.5"
            >
              <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/50" />
              <span class="font-medium">{doc.original}</span>
              <button
                type="button"
                phx-click="remove_staged_document"
                phx-value-ref={doc.ref}
                class="btn btn-ghost btn-xs ml-auto"
              >
                Remove
              </button>
            </li>
          </ul>
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
       |> assign(:upload_slot_target, nil)
       |> assign(:staged_documents, [])
       |> allow_upload(:document, accept: :any, max_entries: 1, max_file_size: 20_000_000)
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
        case attach_staged_documents(scope, socket.assigns.staged_documents, obligation) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Obligation created.")
             |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Obligation created, but some files could not be attached.")
             |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "An open note is required.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("select_create_upload_slot", %{"slot" => "additional"}, socket) do
    {:noreply, assign(socket, :upload_slot_target, :additional)}
  end

  def handle_event("select_create_upload_slot", _params, socket) do
    {:noreply, put_flash(socket, :error, "Completion documents can be added after creation.")}
  end

  def handle_event("clear_create_upload_slot", _params, socket) do
    {:noreply, assign(socket, :upload_slot_target, nil)}
  end

  def handle_event("validate_create_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("stage_create_document", params, socket) do
    scope = socket.assigns.current_scope

    if completion_slot?(params["document_slot"]) do
      {:noreply, put_flash(socket, :error, "Completion documents can be added after creation.")}
    else
      stage_general_document(socket, scope)
    end
  end

  def handle_event("remove_staged_document", %{"ref" => ref}, socket) do
    {removed, kept} =
      Enum.split_with(socket.assigns.staged_documents, &(to_string(&1.ref) == to_string(ref)))

    Enum.each(removed, &Uploads.delete_staged/1)

    {:noreply, assign(socket, :staged_documents, kept)}
  end

  defp stage_general_document(socket, scope) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        upload = %Plug.Upload{
          path: path,
          filename: entry.client_name,
          content_type: entry.client_type
        }

        staged = Uploads.stage(upload, scope.entity.id)

        {:ok,
         %{
           ref: Ecto.UUID.generate(),
           slot: nil,
           path: staged.path,
           original: staged.original,
           content_type: staged.content_type
         }}
      end)

    case results do
      [staged | _] ->
        {:noreply,
         socket
         |> assign(:staged_documents, socket.assigns.staged_documents ++ [staged])
         |> assign(:upload_slot_target, nil)}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a file to upload.")}
    end
  end

  defp attach_staged_documents(_scope, [], obligation), do: {:ok, obligation}

  defp attach_staged_documents(scope, staged_documents, obligation) do
    obligation = Obligations.get_obligation!(scope, obligation.id)
    open_event = open_event!(obligation)

    result =
      Enum.reduce_while(staged_documents, {:ok, obligation}, fn doc, {:ok, ob} ->
        upload = %Plug.Upload{
          path: doc.path,
          filename: doc.original,
          content_type: doc.content_type
        }

        case Obligations.add_document(scope, ob, open_event, upload, nil) do
          {:ok, _} ->
            Uploads.delete_staged(doc)
            {:cont, {:ok, ob}}

          {:error, _} = error ->
            {:halt, error}

          :not_authorise ->
            {:halt, :not_authorise}
        end
      end)

    case result do
      {:ok, obligation} -> {:ok, obligation}
      other -> other
    end
  end

  defp open_event!(%Obligation{} = obligation) do
    case Enum.find(obligation.events, &(&1.status == "open")) do
      %{} = event -> event
      nil -> raise "open event not found for obligation #{obligation.id}"
    end
  end

  defp completion_slot?(nil), do: false
  defp completion_slot?(""), do: false
  defp completion_slot?("additional"), do: false
  defp completion_slot?(_), do: true

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
