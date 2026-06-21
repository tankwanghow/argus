defmodule Argus.Repo.Migrations.AddCompletedInErrorToObligations do
  use Ecto.Migration

  def change do
    alter table(:obligations) do
      add :completed_in_error_at, :utc_datetime

      add :completed_in_error_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :completed_in_error_reason, :string
      add :replaces_id, references(:obligations, type: :binary_id, on_delete: :nilify_all)
      add :replaced_by_id, references(:obligations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:obligations, [:replaces_id])
    create index(:obligations, [:replaced_by_id])
  end
end
