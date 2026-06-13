defmodule Argus.Entities.Membership do
  use Argus.Schema
  import Ecto.Changeset

  schema "memberships" do
    field :role, :string
    field :invited_by_id, :binary_id
    field :accepted_at, :utc_datetime
    field :is_default, :boolean, default: false

    belongs_to :user, Argus.Accounts.User
    belongs_to :entity, Argus.Entities.Entity

    timestamps()
  end

  @roles ~w(admin manager member)

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :invited_by_id, :accepted_at, :is_default])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :entity_id])
  end
end
