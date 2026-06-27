defmodule Tugas.Repo.Migrations.CreateDuties do
  use Ecto.Migration

  def change do
    create table(:duties, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false

      add :duty_type_id,
          references(:duty_types, type: :binary_id, on_delete: :restrict), null: false

      add :series_id, :binary_id, null: false
      add :title, :string, null: false

      add :primary_assignee_id, references(:users, type: :binary_id, on_delete: :restrict)

      add :due_by, :date, null: false
      add :status, :string, null: false, default: "active"
      add :completed_at, :utc_datetime
      add :series_ended_at, :utc_datetime
      add :complete_documents, :string, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create index(:duties, [:entity_id, :status])
    create index(:duties, [:series_id])
    create index(:duties, [:primary_assignee_id])

    create unique_index(:duties, [:series_id],
             where: "status = 'active' AND completed_at IS NULL",
             name: :duties_one_live_cycle_per_series
           )

    create index(:duties, [:series_id],
             where: "series_ended_at IS NOT NULL",
             name: :duties_series_ended
           )

    create table(:duty_collaborators, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :duty_id, references(:duties, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:duty_collaborators, [:duty_id, :user_id])

    create table(:duty_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :duty_id, references(:duties, type: :binary_id, on_delete: :delete_all), null: false

      add :status, :string, null: false
      add :status_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :note, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:duty_events, [:duty_id])
  end
end
