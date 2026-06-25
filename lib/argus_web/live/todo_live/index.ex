defmodule ArgusWeb.TodoLive.Index do
  use ArgusWeb, :live_view

  alias ArgusWeb.ModalEscape
  alias ArgusWeb.TodoLive.IndexHelpers
  alias Argus.Todos.Todo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="todos-page">
        <.header>
          Todos
          <:subtitle>Quick team tasks — separate from duties.</:subtitle>
          <:actions>
            <button
              id="new-todo-btn"
              type="button"
              phx-click="new"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus-mini" class="size-4" /> New todo
            </button>
          </:actions>
        </.header>

        <ul
          :if={@todos != []}
          id="todos-list"
          class="mt-6 divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={todo <- @todos}
            id={"todo-#{todo.id}"}
            class={[
              "p-3 space-y-2",
              Todo.completed?(todo) && "opacity-60"
            ]}
          >
            <div class="flex items-start gap-3">
              <input
                id={"todo-complete-#{todo.id}"}
                type="checkbox"
                class="checkbox checkbox-sm mt-1"
                checked={Todo.completed?(todo)}
                phx-click="toggle_complete"
                phx-value-id={todo.id}
              />
              <div class="flex-1 min-w-0">
                <div class={[
                  "font-medium",
                  Todo.completed?(todo) && "line-through text-base-content/60"
                ]}>
                  {todo.title}
                </div>
                <div class="text-xs text-base-content/50 mt-0.5">
                  Added by {display_name(todo.created_by)}
                  <span :if={Todo.completed?(todo) && todo.completed_by}>
                    · Done by {display_name(todo.completed_by)}
                  </span>
                </div>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={todo.id}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={todo.id}
                  data-confirm="Delete this todo?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </div>
            </div>
            <.audit_trail
              todo={todo}
              logs={Map.get(@audit_by_id, todo.id, [])}
              expanded?={@expanded_audit_id == todo.id}
            />
          </li>
        </ul>
        <p :if={@todos == []} id="todos-empty" class="mt-6 text-sm text-base-content/60">
          No todos yet. Add one to get started.
        </p>
      </div>

      <div :if={@todo_form} id="todo-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">{@modal_title}</h3>
          <.form
            for={@todo_form}
            id="todo-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4 space-y-3"
          >
            <.input field={@todo_form[:title]} type="text" label="Title" required />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="cancel">Cancel</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">{@submit_label}</.button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="cancel">close</button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :todo, Todo, required: true
  attr :logs, :list, required: true
  attr :expanded?, :boolean, required: true

  defp audit_trail(assigns) do
    ~H"""
    <div :if={@logs != []} class="pl-8">
      <button
        type="button"
        phx-click="toggle_audit"
        phx-value-id={@todo.id}
        class="text-xs text-base-content/50 hover:text-base-content"
      >
        {if @expanded?, do: "Hide history", else: "Show history (#{length(@logs)})"}
      </button>
      <ul
        :if={@expanded?}
        id={"todo-audit-#{@todo.id}"}
        class="mt-1 space-y-1 text-xs text-base-content/60"
      >
        <li :for={log <- @logs}>
          <span class="font-medium">{audit_action_label(log.action)}</span>
          by {display_name(log.user)}
          <span :if={log.field}>
            — {log.field}: {log.old_value || "—"} → {log.new_value || "—"}
          </span>
          <span class="text-base-content/40"> · {format_time(log.inserted_at)}</span>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, IndexHelpers.mount_assigns(socket)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, IndexHelpers.open_modal(socket, %Todo{}, nil, "New todo", "Create")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    todo = Argus.Todos.get_todo!(scope, id)
    {:noreply, IndexHelpers.open_modal(socket, todo, todo, "Edit todo", "Save")}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, ModalEscape.close_todo_modal(socket)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, IndexHelpers.close_modal(socket)}
  end

  def handle_event("validate", params, socket) do
    {:noreply, IndexHelpers.handle_validate(socket, params)}
  end

  def handle_event("save", params, socket) do
    case IndexHelpers.handle_save(socket, params) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
      {:not_authorise, socket} -> {:noreply, socket}
    end
  end

  def handle_event("toggle_complete", params, socket) do
    case IndexHelpers.handle_toggle(socket, params) do
      {:ok, socket} -> {:noreply, socket}
      {:not_authorise, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("delete", params, socket) do
    case IndexHelpers.handle_delete(socket, params) do
      {:ok, socket} -> {:noreply, socket}
      {:not_authorise, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("toggle_audit", %{"id" => id}, socket) do
    expanded =
      if socket.assigns.expanded_audit_id == id, do: nil, else: id

    {:noreply, assign(socket, :expanded_audit_id, expanded)}
  end

  defp display_name(%{username: u}) when is_binary(u) and u != "", do: u
  defp display_name(%{email: e}) when is_binary(e), do: e
  defp display_name(_), do: "Unknown"

  defp audit_action_label("created"), do: "Created"
  defp audit_action_label("updated"), do: "Updated"
  defp audit_action_label("completed"), do: "Completed"
  defp audit_action_label("reopened"), do: "Reopened"
  defp audit_action_label("deleted"), do: "Deleted"
  defp audit_action_label(other), do: other

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end
end
