defmodule TugasWeb.EntityLive.Select do
  use TugasWeb, :live_view

  import TugasWeb.EntityPicker

  alias Tugas.Entities
  alias Tugas.Entities.Entity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_simple :if={@mobile?} flash={@flash} current_scope={@current_scope}>
      <.picker
        memberships={@memberships}
        form={@form}
        editing_entity_id={@editing_entity_id}
        edit_form={@edit_form}
        mobile?={true}
      />
    </Layouts.mobile_simple>

    <Layouts.app :if={not @mobile?} flash={@flash} current_scope={@current_scope}>
      <.picker
        memberships={@memberships}
        form={@form}
        editing_entity_id={@editing_entity_id}
        edit_form={@edit_form}
        mobile?={false}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    mobile? = TugasWeb.Device.mobile_from_socket?(socket)
    memberships = Entities.list_entity_memberships(socket.assigns.current_scope.user)
    socket = assign(socket, :mobile?, mobile?)

    cond do
      params["pick"] == "1" ->
        {:ok, assign_picker(socket, memberships)}

      length(memberships) == 1 ->
        {entity, _} = hd(memberships)
        {:ok, redirect(socket, to: entity_dashboard_path(entity, mobile?))}

      true ->
        {:ok, assign_picker(socket, memberships)}
    end
  end

  @impl true
  def handle_event("validate", %{"new_entity" => params}, socket) do
    changeset =
      %Entity{}
      |> Entities.change_entity(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"new_entity" => params}, socket) do
    case Entities.create_entity(socket.assigns.current_scope, params) do
      {:ok, entity} ->
        {:noreply, redirect(socket, to: entity_dashboard_path(entity, socket.assigns.mobile?))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("edit_entity", %{"id" => id}, socket) do
    entity = find_entity(socket.assigns.memberships, id)

    {:noreply,
     socket
     |> assign(:editing_entity_id, entity.id)
     |> assign(:edit_form, edit_form(entity))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_entity_id, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("validate_edit", %{"edit_entity" => params}, socket) do
    entity = find_entity(socket.assigns.memberships, socket.assigns.editing_entity_id)

    changeset =
      entity
      |> Entities.change_entity(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_form, to_form(changeset, as: "edit_entity"))}
  end

  def handle_event("save_entity", %{"entity_id" => id, "edit_entity" => params}, socket) do
    entity = find_entity(socket.assigns.memberships, id)
    scope = socket.assigns.current_scope

    case Entities.update_entity(scope, entity, params) do
      {:ok, updated} ->
        memberships = reload_memberships(scope.user, updated)

        {:noreply,
         socket
         |> assign(:memberships, memberships)
         |> assign(:editing_entity_id, nil)
         |> assign(:edit_form, nil)
         |> put_flash(:info, "Entity updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: "edit_entity"))}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    if socket.assigns[:editing_entity_id] do
      {:noreply, assign(socket, editing_entity_id: nil, edit_form: nil)}
    else
      {:noreply, socket}
    end
  end

  defp assign_picker(socket, memberships) do
    changeset = Entities.change_entity(%Entity{})

    socket
    |> assign(:memberships, memberships)
    |> assign(:editing_entity_id, nil)
    |> assign(:edit_form, nil)
    |> assign_form(changeset)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "new_entity"))
  end

  defp edit_form(%Entity{} = entity) do
    to_form(
      %{
        "name" => entity.name,
        "slug" => entity.slug,
        "timezone" => entity.timezone
      },
      as: "edit_entity"
    )
  end

  defp find_entity(memberships, id) do
    memberships
    |> Enum.find_value(fn {entity, _} -> if entity.id == id, do: entity end)
    |> case do
      %Entity{} = entity -> entity
      _ -> raise ArgumentError, "entity not found: #{inspect(id)}"
    end
  end

  defp reload_memberships(user, %Entity{} = updated) do
    Entities.list_entity_memberships(user)
    |> Enum.map(fn
      {%Entity{id: id}, membership} when id == updated.id ->
        {updated, membership}

      pair ->
        pair
    end)
  end

  defp entity_dashboard_path(%Entity{} = entity, true), do: ~p"/m/#{entity.slug}"
  defp entity_dashboard_path(%Entity{} = entity, false), do: ~p"/entities/#{entity.slug}"
end
