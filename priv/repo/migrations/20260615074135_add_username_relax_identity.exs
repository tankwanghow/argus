defmodule Tugas.Repo.Migrations.AddUsernameRelaxIdentity do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :citext
      modify :email, :citext, null: true, from: {:citext, null: false}
    end

    create unique_index(:users, [:username])

    create constraint(:users, :users_email_or_username_required,
             check: "email IS NOT NULL OR username IS NOT NULL"
           )

    alter table(:entity_invitations) do
      modify :email, :citext, null: true, from: {:citext, null: false}
      add :reusable, :boolean, null: false, default: false
      add :closed_at, :utc_datetime
    end

    drop unique_index(:entity_invitations, [:entity_id, :email],
           name: :entity_invitations_one_pending_per_email
         )

    create unique_index(:entity_invitations, [:entity_id, :email],
             where: "accepted_at IS NULL AND email IS NOT NULL",
             name: :entity_invitations_one_pending_per_email
           )
  end
end
