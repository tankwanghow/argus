defmodule Argus.Obligations.AuditLog do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Obligations.{Event, Obligation}

  schema "obligation_audit_logs" do
    field :field, :string
    field :old_value, :string
    field :new_value, :string

    belongs_to :obligation, Obligation
    belongs_to :obligation_event, Event
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:field, :old_value, :new_value])
    |> validate_required([:field])
  end
end
