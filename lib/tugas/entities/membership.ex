defmodule Tugas.Entities.Membership do
  use Tugas.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "memberships" do
    field :role, :string
    field :invited_by_id, :binary_id
    field :accepted_at, :utc_datetime
    field :disabled_at, :utc_datetime
    field :disabled_by_id, :binary_id
    field :is_default, :boolean, default: false

    belongs_to :user, Tugas.Accounts.User
    belongs_to :entity, Tugas.Entities.Entity

    timestamps()
  end

  @roles ~w(admin manager member)

  @doc """
  Composable query restricting to *active* memberships: accepted and not
  disabled. Single source of truth for "who counts as a usable member" —
  drives seat counting, the assignable-member list, and assignee eligibility.
  """
  def active(query \\ __MODULE__) do
    from m in query, where: not is_nil(m.accepted_at) and is_nil(m.disabled_at)
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :role,
      :invited_by_id,
      :accepted_at,
      :disabled_at,
      :disabled_by_id,
      :is_default
    ])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :entity_id])
  end
end
