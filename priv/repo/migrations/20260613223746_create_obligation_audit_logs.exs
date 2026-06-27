defmodule Tugas.Repo.Migrations.CreateObligationAuditLogs do
  use Ecto.Migration

  def change do
    create table(:obligation_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :obligation_id, references(:obligations, type: :binary_id, on_delete: :delete_all)

      add :obligation_event_id,
          references(:obligation_events, type: :binary_id, on_delete: :delete_all)

      add :field, :string, null: false
      add :old_value, :text
      add :new_value, :text
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:obligation_audit_logs, [:obligation_id])
    create index(:obligation_audit_logs, [:obligation_event_id])
  end
end
