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
        <.header>New obligation</.header>

        <.form
          for={@form}
          id="obligation-create-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 space-y-4 max-w-xl"
        >
          <.input field={@form[:title]} type="text" label="Title" required />
          <.input
            field={@form[:obligation_type_id]}
            type="select"
            label="Type"
            options={@type_options}
            prompt="Choose a type"
            required
          />
          <.input
            field={@form[:primary_assignee_id]}
            type="select"
            label="Primary assignee"
            options={@member_options}
            prompt="Choose assignee"
            required
          />
          <div class="fieldset mb-2">
            <label class="label mb-1" for="collaborator-ids">Collaborators (optional)</label>
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
          <.input field={@form[:due_by]} type="date" label="Due by" required />
          <.input field={@form[:open_note]} type="textarea" label="Open note (optional)" />
          <.button phx-disable-with="Creating..." class="btn btn-primary">Create obligation</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Argus.Authorization.can?(socket.assigns.current_scope, :create_obligation) do
      {:ok, load_form(socket)}
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
        {:noreply,
         socket
         |> put_flash(:info, "Obligation created.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

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

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
