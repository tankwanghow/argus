defmodule Tugas.Repo.Migrations.AddDisableToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :disabled_at, :utc_datetime
      add :disabled_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:memberships, [:entity_id, :disabled_at])
  end
end
