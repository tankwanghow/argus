defmodule Tugas.Repo.Migrations.AddTodoCancelAndEscalation do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :canceled_at, :utc_datetime
      add :canceled_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :escalated_duty_id,
          references(:duties, type: :binary_id, on_delete: :nilify_all)

      add :escalated_at, :utc_datetime
      add :escalated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:todos, [:escalated_duty_id])
  end
end
