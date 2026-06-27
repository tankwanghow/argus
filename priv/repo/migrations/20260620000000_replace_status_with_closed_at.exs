defmodule Tugas.Repo.Migrations.ReplaceStatusWithClosedAt do
  use Ecto.Migration

  def up do
    drop index(:duties, [:entity_id, :status])

    drop unique_index(:duties, [:series_id], name: :duties_one_live_cycle_per_series)

    alter table(:duties) do
      add :closed_at, :utc_datetime
      remove :status
    end

    create index(:duties, [:entity_id])

    create unique_index(:duties, [:series_id],
             where: "completed_at IS NULL AND closed_at IS NULL",
             name: :duties_one_live_cycle_per_series
           )
  end

  def down do
    drop unique_index(:duties, [:series_id], name: :duties_one_live_cycle_per_series)

    drop index(:duties, [:entity_id])

    alter table(:duties) do
      add :status, :string, null: false, default: "active"
      remove :closed_at
    end

    create index(:duties, [:entity_id, :status])

    create unique_index(:duties, [:series_id],
             where: "status = 'active' AND completed_at IS NULL",
             name: :duties_one_live_cycle_per_series
           )
  end
end
