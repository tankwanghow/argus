defmodule Tugas.Obligations.Collaborator do
  use Tugas.Schema
  import Ecto.Changeset

  alias Tugas.Accounts.User
  alias Tugas.Obligations.Obligation

  schema "obligation_collaborators" do
    belongs_to :obligation, Obligation
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(collaborator, attrs \\ %{}) do
    collaborator
    |> cast(attrs, [])
    |> validate_required([])
  end
end
