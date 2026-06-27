defmodule Tugas.Repo.Migrations.AddDutySortIndexes do
  use Ecto.Migration

  def change do
    create index(:duties, [:entity_id, :due_by, :id])

    create index(:duties, [:entity_id, :due_by, :id],
             name: :duties_completed_due_idx,
             where: "completed_at IS NOT NULL"
           )

    create index(:duties, [:entity_id, :due_by, :id],
             name: :duties_skipped_due_idx,
             where: "closed_at IS NOT NULL"
           )
  end
end
