defmodule Tugas.Repo.Migrations.AddCompletedInErrorToDuties do
  use Ecto.Migration

  def change do
    alter table(:duties) do
      add :completed_in_error_at, :utc_datetime

      add :completed_in_error_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :completed_in_error_reason, :string
      add :replaces_id, references(:duties, type: :binary_id, on_delete: :nilify_all)
      add :replaced_by_id, references(:duties, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:duties, [:replaces_id])
    create index(:duties, [:replaced_by_id])
  end
end
