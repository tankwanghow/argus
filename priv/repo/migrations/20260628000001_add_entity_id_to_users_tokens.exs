defmodule Tugas.Repo.Migrations.AddEntityIdToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all)
    end

    create index(:users_tokens, [:entity_id])
  end
end
