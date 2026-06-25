defmodule Argus.TodosTest do
  use Argus.DataCase, async: true

  @moduletag :todos

  alias Argus.Todos
  alias Argus.Todos.Todo

  import Argus.EntitiesFixtures, only: [entity_scope_fixture: 0]
  import Argus.ObligationsFixtures, only: [member_scope_on_entity: 1]

  describe "create_todo/2 and list_todos/1" do
    test "creates a todo visible to all team members" do
      creator = entity_scope_fixture()
      teammate = member_scope_on_entity(creator.entity)

      assert {:ok, todo} = Todos.create_todo(creator, %{title: "Buy supplies"})
      assert todo.title == "Buy supplies"
      assert todo.entity_id == creator.entity.id
      assert todo.created_by_id == creator.user.id
      assert is_nil(todo.completed_at)

      listed = Todos.list_todos(teammate)
      assert length(listed) == 1
      assert hd(listed).id == todo.id
    end

    test "rejects blank title" do
      scope = entity_scope_fixture()
      assert {:error, changeset} = Todos.create_todo(scope, %{title: ""})
      assert "can't be blank" in errors_on(changeset).title
    end
  end

  describe "update_todo/3" do
    test "updates title and records audit" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Draft memo"})

      assert {:ok, updated} = Todos.update_todo(scope, todo, %{title: "Send memo"})
      assert updated.title == "Send memo"

      [created, updated_entry] = Todos.list_audit_logs(updated)
      assert created.action == "created"
      assert updated_entry.action == "updated"
      assert updated_entry.field == "title"
      assert updated_entry.old_value == "Draft memo"
      assert updated_entry.new_value == "Send memo"
      assert updated_entry.user_id == scope.user.id
    end
  end

  describe "toggle_complete/2" do
    test "completes and reopens with audit trail" do
      creator = entity_scope_fixture()
      finisher = member_scope_on_entity(creator.entity)
      {:ok, todo} = Todos.create_todo(creator, %{title: "Call vendor"})

      assert {:ok, completed} = Todos.toggle_complete(finisher, todo)
      assert %DateTime{} = completed.completed_at
      assert completed.completed_by_id == finisher.user.id

      logs = Todos.list_audit_logs(completed)
      assert Enum.any?(logs, &(&1.action == "completed" && &1.user_id == finisher.user.id))

      assert {:ok, reopened} = Todos.toggle_complete(creator, completed)
      assert is_nil(reopened.completed_at)
      assert Enum.any?(Todos.list_audit_logs(reopened), &(&1.action == "reopened"))
    end
  end

  describe "delete_todo/2" do
    test "deletes todo and leaves audit entry" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Scratch item"})
      assert {:ok, _} = Todos.delete_todo(scope, todo)
      assert [] = Todos.list_todos(scope)

      audit =
        Argus.Repo.all(Argus.Todos.AuditLog)
        |> Enum.find(&(&1.action == "deleted" && &1.old_value == "Scratch item"))

      assert audit
      assert audit.action == "deleted"
      assert audit.old_value == "Scratch item"
      assert audit.user_id == scope.user.id
    end
  end

  describe "cross-user workflow" do
    test "full sequence twice for consistency" do
      for _ <- 1..2 do
        creator = entity_scope_fixture()
        teammate = member_scope_on_entity(creator.entity)

        {:ok, todo} = Todos.create_todo(creator, %{title: "Team task #{System.unique_integer()}"})
        assert hd(Todos.list_todos(teammate)).id == todo.id

        assert {:ok, todo} = Todos.update_todo(teammate, todo, %{title: "Updated team task"})
        assert {:ok, todo} = Todos.toggle_complete(teammate, todo)
        assert Todo.completed?(todo)

        logs = Todos.list_audit_logs(todo)
        actions = Enum.map(logs, & &1.action)
        assert "created" in actions
        assert "updated" in actions
        assert "completed" in actions

        assert {:ok, _} = Todos.delete_todo(creator, todo)
        assert [] = Todos.list_todos(teammate)
      end
    end
  end
end
