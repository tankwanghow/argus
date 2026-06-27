defmodule Tugas.Entities.Invitation do
  use Tugas.Schema
  import Ecto.Changeset

  schema "entity_invitations" do
    field :email, :string
    field :role, :string
    field :token, :binary
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :reusable, :boolean, default: false
    field :closed_at, :utc_datetime

    belongs_to :entity, Tugas.Entities.Entity
    belongs_to :invited_by, Tugas.Accounts.User

    timestamps(updated_at: false)
  end

  @roles ~w(admin manager member)

  @doc """
  Encodes a raw binary token into a URL-safe string for invite links.
  """
  def encode_token(token) when is_binary(token) do
    Base.url_encode64(token, padding: false)
  end

  @doc """
  Decodes a URL-safe token string back to its raw binary form.
  Returns `:error` on malformed input.
  """
  def decode_token(encoded) when is_binary(encoded) do
    Base.url_decode64(encoded, padding: false)
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :token, :expires_at, :accepted_at, :reusable, :closed_at])
    |> validate_required([:role, :token, :expires_at])
    |> validate_inclusion(:role, @roles)
    |> maybe_validate_email_format()
    |> unique_constraint([:entity_id, :email], name: :entity_invitations_one_pending_per_email)
    |> unique_constraint(:token)
  end

  defp maybe_validate_email_format(changeset) do
    if get_field(changeset, :email) do
      validate_format(changeset, :email, ~r/^[^@,;\s]+@[^@,;\s]+$/)
    else
      changeset
    end
  end
end
