defmodule Argus.Repo.Migrations.CreateEntitiesTables do
  use Ecto.Migration

  def change do
    create table(:entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :citext, null: false
      add :name, :string, null: false
      add :timezone, :string, null: false, default: "Asia/Kuala_Lumpur"
      add :plan, :string, null: false, default: "free"
      add :seat_limit, :integer, null: false, default: 5
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:entities, [:slug], where: "deleted_at IS NULL")

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :accepted_at, :utc_datetime
      add :is_default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :entity_id])

    create unique_index(:memberships, [:user_id],
             where: "is_default = true",
             name: :memberships_one_default_per_user
           )

    create table(:entity_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :role, :string, null: false
      add :token, :binary, null: false

      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:entity_invitations, [:entity_id, :email],
             where: "accepted_at IS NULL",
             name: :entity_invitations_one_pending_per_email
           )

    create unique_index(:entity_invitations, [:token])
  end
end
