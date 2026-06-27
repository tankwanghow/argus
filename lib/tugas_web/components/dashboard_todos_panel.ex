defmodule TugasWeb.DashboardTodosPanel do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TugasWeb.Endpoint,
    router: TugasWeb.Router,
    statics: TugasWeb.static_paths()

  alias Tugas.Todos.Todo
  alias TugasWeb.TodoLive.IndexHelpers

  attr :todos, :list, required: true
  attr :slug, :string, required: true
  attr :row_effects, :map, default: %{}

  def dashboard_todos_panel(assigns) do
    ~H"""
    <aside
      id="dashboard-todos"
      class="flex flex-1 flex-col min-h-0 rounded-lg border border-base-300 bg-base-200/40 p-3"
    >
      <div class="flex shrink-0 items-center gap-2 pb-3">
        <h2 class="text-lg font-semibold">Todos</h2>
        <.link navigate={~p"/entities/#{@slug}/todos"} class="text-sm link link-primary">
          View all →
        </.link>
      </div>

      <ul
        :if={@todos != []}
        id="dashboard-todos-list"
        class="flex-1 min-h-0 space-y-2 overflow-y-auto"
      >
        <li
          :for={todo <- @todos}
          id={"dashboard-todo-#{todo.id}"}
          phx-hook="TodoRowEffect"
          data-todo-id={todo.id}
          data-effect={IndexHelpers.row_effect_name(@row_effects, todo.id)}
          class={[
            "flex items-start gap-2 px-1 py-1 border border-transparent rounded",
            IndexHelpers.row_effect_class(@row_effects, todo.id)
          ]}
        >
          <input
            id={"dashboard-todo-complete-#{todo.id}"}
            type="checkbox"
            class="checkbox checkbox-sm mt-0.5"
            checked={Todo.completed?(todo)}
            phx-click="toggle_todo_complete"
            phx-value-id={todo.id}
          />
          <span class="text-sm truncate">{todo.title}</span>
        </li>
      </ul>

      <p :if={@todos == []} class="flex-1 text-sm text-base-content/60">
        No open todos.
        <.link navigate={~p"/entities/#{@slug}/todos"} class="link link-primary">Add one</.link>
      </p>
    </aside>
    """
  end
end
