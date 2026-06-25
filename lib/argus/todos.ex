defmodule Argus.Todos do
  @moduledoc """
  Quick todos — entity-scoped, team-visible tasks separate from obligations.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Argus.Accounts.Scope
  alias Argus.Authorization
  alias Argus.Repo
  alias Argus.Todos.{AuditLog, Todo}

  def list_todos(%Scope{entity: entity}) do
    Todo
    |> where([t], t.entity_id == ^entity.id)
    |> order_by([t], asc: is_nil(t.completed_at), desc: t.inserted_at)
    |> preload([:created_by, :completed_by])
    |> Repo.all()
  end

  def get_todo!(%Scope{entity: entity}, id) do
    Todo
    |> where([t], t.id == ^id and t.entity_id == ^entity.id)
    |> preload([:created_by, :completed_by])
    |> Repo.one!()
  end

  def change_todo(%Todo{} = todo, attrs \\ %{}) do
    Todo.changeset(todo, attrs)
  end

  def create_todo(%Scope{entity: entity, user: user} = scope, attrs) do
    if Authorization.can?(scope, :create_todo) do
      Multi.new()
      |> Multi.insert(
        :todo,
        %Todo{entity_id: entity.id, created_by_id: user.id}
        |> Todo.changeset(attrs)
      )
      |> Multi.run(:audit, fn repo, %{todo: todo} ->
        insert_audit!(repo, scope, todo, "created", nil, nil, todo.title)
        {:ok, :created}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{todo: todo}} -> {:ok, todo}
        {:error, :todo, changeset, _} -> {:error, changeset}
        {:error, _op, reason, _} -> {:error, reason}
      end
    else
      :not_authorise
    end
  end

  def update_todo(%Scope{} = scope, %Todo{} = todo, attrs) do
    if Authorization.can?(scope, :edit_todo) do
      changeset = Todo.changeset(todo, attrs)

      if changeset.valid? && changeset.changes == %{} do
        {:ok, todo}
      else
        Multi.new()
        |> Multi.update(:todo, changeset)
        |> Multi.run(:audit, fn repo, %{todo: updated} ->
          audit_title_change(repo, scope, todo, updated)
          {:ok, :audited}
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{todo: updated}} -> {:ok, updated}
          {:error, :todo, changeset, _} -> {:error, changeset}
          {:error, _op, reason, _} -> {:error, reason}
        end
      end
    else
      :not_authorise
    end
  end

  def toggle_complete(%Scope{user: user} = scope, %Todo{} = todo) do
    if Authorization.can?(scope, :complete_todo) do
      if Todo.completed?(todo) do
        reopen_todo(scope, todo)
      else
        complete_todo(scope, todo, user.id)
      end
    else
      :not_authorise
    end
  end

  def delete_todo(%Scope{} = scope, %Todo{} = todo) do
    if Authorization.can?(scope, :delete_todo) do
      Multi.new()
      |> Multi.run(:audit, fn repo, _ ->
        insert_audit!(repo, scope, todo, "deleted", "title", todo.title, nil)
        {:ok, :audited}
      end)
      |> Multi.delete(:todo, todo)
      |> Repo.transaction()
      |> case do
        {:ok, %{todo: deleted}} -> {:ok, deleted}
        {:error, _op, reason, _} -> {:error, reason}
      end
    else
      :not_authorise
    end
  end

  def list_audit_logs(%Todo{} = todo) do
    AuditLog
    |> where([l], l.todo_id == ^todo.id)
    |> order_by([l], asc: l.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  defp complete_todo(scope, todo, user_id) do
    Multi.new()
    |> Multi.update(:todo, Todo.complete_changeset(todo, user_id))
    |> Multi.run(:audit, fn repo, %{todo: updated} ->
      insert_audit!(repo, scope, updated, "completed", nil, nil, nil)
      {:ok, :completed}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{todo: updated}} -> {:ok, updated}
      {:error, _op, reason, _} -> {:error, reason}
    end
  end

  defp reopen_todo(scope, todo) do
    Multi.new()
    |> Multi.update(:todo, Todo.reopen_changeset(todo))
    |> Multi.run(:audit, fn repo, %{todo: updated} ->
      insert_audit!(repo, scope, updated, "reopened", nil, nil, nil)
      {:ok, :reopened}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{todo: updated}} -> {:ok, updated}
      {:error, _op, reason, _} -> {:error, reason}
    end
  end

  defp audit_title_change(repo, scope, old, updated) do
    if old.title != updated.title do
      insert_audit!(repo, scope, updated, "updated", "title", old.title, updated.title)
    end

    :ok
  end

  defp insert_audit!(repo, scope, todo, action, field, old_value, new_value) do
    %AuditLog{todo_id: todo.id, user_id: scope.user.id}
    |> AuditLog.changeset(%{
      action: action,
      field: field,
      old_value: old_value,
      new_value: new_value
    })
    |> repo.insert!()
  end
end
