defmodule Tugas.Repo.Migrations.AddQueryPerformanceIndexes do
  use Ecto.Migration

  def change do
    create index(:duties, [:entity_id, :due_by, :id],
             name: :duties_live_due_idx,
             where: "completed_at IS NULL AND closed_at IS NULL"
           )

    create index(:duties, [:entity_id, :completed_at, :id],
             name: :duties_completed_at_idx,
             where: "completed_at IS NOT NULL"
           )

    create index(:duties, [:entity_id, :closed_at, :id],
             name: :duties_closed_at_idx,
             where: "closed_at IS NOT NULL"
           )

    create index(:duties, [:entity_id, :id],
             name: :duties_live_someday_idx,
             where: "completed_at IS NULL AND closed_at IS NULL AND due_by IS NULL"
           )

    create index(:duty_collaborators, [:user_id])

    create index(:duty_events, [:duty_id, :inserted_at])
  end
end
