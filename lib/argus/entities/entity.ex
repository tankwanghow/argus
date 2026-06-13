defmodule Argus.Entities.Entity do
  @moduledoc false
  use Argus.Schema

  schema "entities" do
    field :slug, :string
    field :name, :string
    field :timezone, :string
    field :plan, :string, default: "free"
    field :seat_limit, :integer, default: 5
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :binary_id

    timestamps()
  end
end