defmodule ArgusWeb.EntityLive.Select do
  use ArgusWeb, :live_view

  alias Argus.Entities
  alias Argus.Entities.Entity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <.header>
          Your entities
          <:subtitle>Pick an entity to enter, or create a new one.</:subtitle>
        </.header>

        <ul id="entities" class="mt-6 divide-y divide-base-300">
          <li
            :for={{entity, membership} <- @memberships}
            id={"entity-#{entity.id}"}
            class="py-3 flex items-center justify-between gap-3"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium">{entity.name}</span>
              <span
                :if={membership.is_default}
                class="badge badge-sm badge-primary"
                title="Your default entity"
              >
                Default
              </span>
            </div>
            <.link navigate={~p"/entities/#{entity.slug}"} class="btn btn-primary btn-sm">
              Enter
            </.link>
          </li>
          <li :if={@memberships == []} class="py-6 text-base-content/60">
            No entities yet.
          </li>
        </ul>

        <div class="mt-10">
          <.header>Create an entity</.header>
          <.form
            for={@form}
            id="new-entity-form"
            phx-submit="save"
            phx-change="validate"
            class="mt-4 space-y-3"
          >
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input
              field={@form[:slug]}
              type="text"
              label="Slug"
              class="w-full input font-mono"
              required
              placeholder="lowercase-with-hyphens"
            />
            <.button phx-disable-with="Creating..." class="btn btn-primary">
              Create entity
            </.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    memberships = Entities.list_entity_memberships(socket.assigns.current_scope.user)

    if length(memberships) == 1 do
      {entity, _} = hd(memberships)
      {:ok, push_navigate(socket, to: ~p"/entities/#{entity.slug}")}
    else
      changeset = Entities.change_entity(%Entity{})
      {:ok, socket |> assign(:memberships, memberships) |> assign_form(changeset)}
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
        {:noreply, push_navigate(socket, to: ~p"/entities/#{entity.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "entity"))
  end
end
