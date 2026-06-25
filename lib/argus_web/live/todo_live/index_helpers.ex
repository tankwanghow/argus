defmodule ArgusWeb.TodoLive.IndexHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Argus.Todos
  alias Argus.Todos.Todo

  def mount_assigns(socket) do
    socket
    |> assign(:todo_form, nil)
    |> assign(:editing, nil)
    |> assign(:expanded_audit_id, nil)
    |> load_todos()
  end

  def load_todos(socket) do
    scope = socket.assigns.current_scope

    case {Todos.list_todos(scope), Todos.list_entity_audit_logs(scope)} do
      {:not_authorise, _} ->
        assign(socket, todos: [], audit_by_id: %{}, entity_activity: [])

      {_, :not_authorise} ->
        assign(socket, todos: [], audit_by_id: %{}, entity_activity: [])

      {{:ok, todos}, {:ok, entity_activity}} ->
        audit_by_id =
          Map.new(todos, fn todo ->
            {todo.id, Todos.list_audit_logs(todo)}
          end)

        socket
        |> assign(:todos, todos)
        |> assign(:audit_by_id, audit_by_id)
        |> assign(:entity_activity, entity_activity)
    end
  end

  def open_modal(socket, template, editing, title, submit_label) do
    changeset = Todos.change_todo(template)

    socket
    |> assign(:todo_form, to_form(changeset, as: "todo"))
    |> assign(:editing, editing)
    |> assign(:modal_title, title)
    |> assign(:submit_label, submit_label)
  end

  def close_modal(socket) do
    assign(socket, todo_form: nil, editing: nil)
  end

  def handle_validate(socket, %{"todo" => params}) do
    template = socket.assigns.editing || %Todo{}
    changeset = Todos.change_todo(template, params) |> Map.put(:action, :validate)

    assign(socket, :todo_form, to_form(changeset, as: "todo"))
  end

  def handle_save(socket, %{"todo" => params}) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing do
        nil -> Todos.create_todo(scope, params)
        %Todo{} = todo -> Todos.update_todo(scope, todo, params)
      end

    case result do
      {:ok, _todo} ->
        {:ok,
         socket
         |> put_flash(:info, "Todo saved.")
         |> close_modal()
         |> load_todos()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, assign(socket, :todo_form, to_form(changeset, as: "todo"))}

      :not_authorise ->
        {:not_authorise,
         socket
         |> put_flash(:error, "Not authorized.")
         |> close_modal()}

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> close_modal()
         |> load_todos()}
    end
  end

  def handle_edit(socket, id) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        {:ok, open_modal(socket, todo, todo, "Edit todo", "Save")}

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_todos()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_toggle(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        case Todos.toggle_complete(scope, todo) do
          {:ok, _todo} ->
            {:ok, load_todos(socket)}

          :not_authorise ->
            {:not_authorise, socket |> put_flash(:error, "Not authorized.")}

          :not_found ->
            {:not_found,
             socket
             |> put_flash(:error, "Todo not found.")
             |> load_todos()}

          {:error, _} ->
            {:error, put_flash(socket, :error, "Could not update todo.")}
        end

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_todos()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_delete(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        case Todos.delete_todo(scope, todo) do
          {:ok, _} ->
            {:ok,
             socket
             |> put_flash(:info, "Todo deleted.")
             |> load_todos()}

          :not_authorise ->
            {:not_authorise, socket |> put_flash(:error, "Not authorized.")}

          :not_found ->
            {:not_found,
             socket
             |> put_flash(:error, "Todo not found.")
             |> load_todos()}

          {:error, _} ->
            {:error, put_flash(socket, :error, "Could not delete todo.")}
        end

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_todos()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_result({_status, socket}) do
    {:noreply, socket}
  end
end
