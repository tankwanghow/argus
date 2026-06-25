defmodule Argus.Todos.Todo do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Entities.Entity
  alias Argus.Todos.AuditLog

  schema "todos" do
    field :title, :string
    field :completed_at, :utc_datetime

    belongs_to :entity, Entity
    belongs_to :created_by, User, foreign_key: :created_by_id
    belongs_to :completed_by, User, foreign_key: :completed_by_id

    has_many :audit_logs, AuditLog

    timestamps(type: :utc_datetime)
  end

  @title_max 200

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: @title_max)
  end

  def complete_changeset(todo, user_id, at \\ DateTime.utc_now(:second)) do
    todo
    |> change(%{completed_at: at, completed_by_id: user_id})
  end

  def reopen_changeset(todo) do
    todo
    |> change(%{completed_at: nil, completed_by_id: nil})
  end

  def completed?(%__MODULE__{completed_at: %DateTime{}}), do: true
  def completed?(_), do: false
end
