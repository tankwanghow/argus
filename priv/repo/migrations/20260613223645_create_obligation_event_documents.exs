defmodule Argus.Repo.Migrations.CreateObligationEventDocuments do
  use Ecto.Migration

  def change do
    create table(:obligation_event_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :obligation_event_id,
          references(:obligation_events, type: :binary_id, on_delete: :delete_all), null: false

      add :file, :map, null: false
      add :document_slot, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :voided_at, :utc_datetime
      add :voided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :void_reason, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:obligation_event_documents, [:obligation_event_id])
  end
end
