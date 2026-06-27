defmodule Tugas.Repo.Migrations.AddSoftDeleteToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:todos, [:entity_id, :deleted_at])
  end
end
