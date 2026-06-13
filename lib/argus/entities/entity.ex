defmodule Argus.Entities.Entity do
  use Argus.Schema
  import Ecto.Changeset

  schema "entities" do
    field :slug, :string
    field :name, :string
    field :timezone, :string, default: "Asia/Kuala_Lumpur"
    field :plan, :string, default: "free"
    field :seat_limit, :integer, default: 5
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :binary_id

    has_many :memberships, Argus.Entities.Membership

    timestamps()
  end

  @doc false
  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:slug, :name, :timezone, :plan, :seat_limit])
    |> validate_required([:slug, :name])
    |> validate_number(:seat_limit, greater_than: 0)
    |> unique_constraint(:slug)
  end
end
