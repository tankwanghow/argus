defmodule Tugas.Repo.Migrations.CreateDutyAuditLogs do
  use Ecto.Migration

  def change do
    create table(:duty_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :duty_id, references(:duties, type: :binary_id, on_delete: :delete_all)

      add :duty_event_id,
          references(:duty_events, type: :binary_id, on_delete: :delete_all)

      add :field, :string, null: false
      add :old_value, :text
      add :new_value, :text
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:duty_audit_logs, [:duty_id])
    create index(:duty_audit_logs, [:duty_event_id])
  end
end
