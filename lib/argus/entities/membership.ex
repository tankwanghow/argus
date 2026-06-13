defmodule Argus.Entities.Membership do
  @moduledoc false
  use Argus.Schema

  schema "memberships" do
    field :role, :string
    field :invited_by_id, :binary_id
    field :accepted_at, :utc_datetime
    field :is_default, :boolean, default: false

    belongs_to :user, Argus.Accounts.User
    belongs_to :entity, Argus.Entities.Entity

    timestamps()
  end
end