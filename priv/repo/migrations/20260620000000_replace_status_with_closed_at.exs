defmodule Tugas.Repo.Migrations.ReplaceStatusWithClosedAt do
  use Ecto.Migration

  def up do
    drop index(:obligations, [:entity_id, :status])

    drop unique_index(:obligations, [:series_id], name: :obligations_one_live_cycle_per_series)

    alter table(:obligations) do
      add :closed_at, :utc_datetime
      remove :status
    end

    create index(:obligations, [:entity_id])

    create unique_index(:obligations, [:series_id],
             where: "completed_at IS NULL AND closed_at IS NULL",
             name: :obligations_one_live_cycle_per_series
           )
  end

  def down do
    drop unique_index(:obligations, [:series_id], name: :obligations_one_live_cycle_per_series)

    drop index(:obligations, [:entity_id])

    alter table(:obligations) do
      add :status, :string, null: false, default: "active"
      remove :closed_at
    end

    create index(:obligations, [:entity_id, :status])

    create unique_index(:obligations, [:series_id],
             where: "status = 'active' AND completed_at IS NULL",
             name: :obligations_one_live_cycle_per_series
           )
  end
end
