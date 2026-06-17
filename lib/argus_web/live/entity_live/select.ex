defmodule ArgusWeb.EntityLive.Select do
  use ArgusWeb, :live_view

  import ArgusWeb.EntityPicker

  alias Argus.Entities
  alias Argus.Entities.Entity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_simple :if={@mobile?} flash={@flash} current_scope={@current_scope}>
      <.picker memberships={@memberships} form={@form} />
    </Layouts.mobile_simple>

    <Layouts.app :if={not @mobile?} flash={@flash} current_scope={@current_scope}>
      <.picker memberships={@memberships} form={@form} />
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    mobile? = mobile_ui?(socket)
    memberships = Entities.list_entity_memberships(socket.assigns.current_scope.user)
    socket = assign(socket, :mobile?, mobile?)

    cond do
      params["pick"] == "1" ->
        {:ok, assign_picker(socket, memberships)}

      length(memberships) == 1 ->
        {entity, _} = hd(memberships)
        {:ok, redirect(socket, to: ~p"/entities/#{entity.slug}")}

      true ->
        {:ok, assign_picker(socket, memberships)}
    end
  end

  @impl true
  def handle_event("validate", %{"entity" => params}, socket) do
    changeset =
      %Entity{}
      |> Entities.change_entity(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"entity" => params}, socket) do
    case Entities.create_entity(socket.assigns.current_scope, params) do
      {:ok, entity} ->
        {:noreply, redirect(socket, to: ~p"/entities/#{entity.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_picker(socket, memberships) do
    changeset = Entities.change_entity(%Entity{})
    socket |> assign(:memberships, memberships) |> assign_form(changeset)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "entity"))
  end

  defp mobile_ui?(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :user_agent) do
      ua when is_binary(ua) -> ArgusWeb.Device.mobile_user_agent?(ua)
      _ -> false
    end
  end
end
