defmodule Tugas.Todos.AuditLog do
  use Tugas.Schema
  import Ecto.Changeset

  alias Tugas.Accounts.User
  alias Tugas.Todos.Todo

  @actions ~w(created updated completed reopened deleted canceled escalated)

  def actions, do: @actions

  schema "todo_audit_logs" do
    field :action, :string
    field :field, :string
    field :old_value, :string
    field :new_value, :string

    belongs_to :todo, Todo
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:action, :field, :old_value, :new_value])
    |> validate_required([:action])
    |> validate_inclusion(:action, @actions)
  end
end
