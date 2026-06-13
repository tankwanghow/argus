defmodule Argus.Entities.Invitation do
  use Argus.Schema
  import Ecto.Changeset

  schema "entity_invitations" do
    field :email, :string
    field :role, :string
    field :token, :binary
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :entity, Argus.Entities.Entity
    belongs_to :invited_by, Argus.Accounts.User

    timestamps(updated_at: false)
  end

  @roles ~w(admin manager member)

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :token, :expires_at, :accepted_at])
    |> validate_required([:email, :role, :token, :expires_at])
    |> validate_inclusion(:role, @roles)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/)
    |> unique_constraint([:entity_id, :email], name: :entity_invitations_one_pending_per_email)
    |> unique_constraint(:token)
  end
end