defmodule Tugas.Duties.AuditLog do
  use Tugas.Schema
  import Ecto.Changeset

  alias Tugas.Accounts.User
  alias Tugas.Duties.{Event, Duty}

  schema "duty_audit_logs" do
    field :field, :string
    field :old_value, :string
    field :new_value, :string

    belongs_to :duty, Duty
    belongs_to :duty_event, Event
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
