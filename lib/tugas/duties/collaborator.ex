defmodule Tugas.Duties.Collaborator do
  use Tugas.Schema
  import Ecto.Changeset

  alias Tugas.Accounts.User
  alias Tugas.Duties.Duty

  schema "duty_collaborators" do
    belongs_to :duty, Duty
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
