defmodule Tugas.Repo.Migrations.CreateDutyTypes do
  use Ecto.Migration

  def change do
    create table(:duty_types, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :recurring_interval, :string, null: false, default: "none"
      add :complete_documents, :string, null: false, default: ""
      add :reminder_offsets, :string, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create unique_index(:duty_types, [:entity_id, :name])
  end
end
