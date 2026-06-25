defmodule Argus.Repo.Migrations.CreateTodos do
  use Ecto.Migration

  def change do
    create table(:todos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :completed_at, :utc_datetime
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :completed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:todos, [:entity_id])
    create index(:todos, [:entity_id, :completed_at])

    create table(:todo_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :field, :string
      add :old_value, :text
      add :new_value, :text
      add :todo_id, references(:todos, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:todo_audit_logs, [:todo_id])
  end
end
