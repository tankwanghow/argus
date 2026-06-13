defmodule Argus.Obligations.EventDocument do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Obligations.Event

  schema "obligation_event_documents" do
    field :file, :map
    field :document_slot, :string
    field :voided_at, :utc_datetime
    field :void_reason, :string

    belongs_to :obligation_event, Event
    belongs_to :user, User
    belongs_to :voided_by, User, foreign_key: :voided_by_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:document_slot, :file, :voided_at, :voided_by_id, :void_reason])
    |> validate_required([:file])
  end
end
