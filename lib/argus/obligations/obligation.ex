defmodule Argus.Obligations.Obligation do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Entities.Entity
  alias Argus.Obligations.{Collaborator, Event, Type}

  schema "obligations" do
    field :series_id, :binary_id
    field :title, :string
    field :due_by, :date
    field :status, :string, default: "active"
    field :completed_at, :utc_datetime
    field :series_ended_at, :utc_datetime
    field :complete_documents, :string, default: ""
    field :open_note, :string, virtual: true

    field :completed_in_error_at, :utc_datetime
    field :completed_in_error_reason, :string

    belongs_to :entity, Entity
    belongs_to :obligation_type, Type
    belongs_to :primary_assignee, User, foreign_key: :primary_assignee_id
    belongs_to :completed_in_error_by, User, foreign_key: :completed_in_error_by_id
    belongs_to :replaces, __MODULE__, foreign_key: :replaces_id
    belongs_to :replaced_by, __MODULE__, foreign_key: :replaced_by_id

    has_many :events, Event
    has_many :collaborators, Collaborator

    timestamps()
  end

  @cast_fields ~w(title obligation_type_id primary_assignee_id due_by open_note)a

  @doc false
  def changeset(obligation, attrs) do
    obligation
    |> cast(attrs, @cast_fields)
    |> validate_required([:title, :obligation_type_id, :due_by])
    |> validate_length(:title, max: 30)
    |> normalize_blank_assignee()
    |> validate_inclusion(:status, ["active", "cancelled"])
    |> unique_constraint(:series_id, name: :obligations_one_live_cycle_per_series)
  end

  defp normalize_blank_assignee(changeset) do
    case get_change(changeset, :primary_assignee_id) do
      "" -> put_change(changeset, :primary_assignee_id, nil)
      _ -> changeset
    end
  end
end
