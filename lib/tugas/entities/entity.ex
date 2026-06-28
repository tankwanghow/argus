defmodule Tugas.Entities.Entity do
  use Tugas.Schema
  import Ecto.Changeset

  alias Tugas.Entities.Country
  alias Tugas.Entities.MalaysiaRegion

  schema "entities" do
    field :slug, :string
    field :name, :string
    field :timezone, :string, default: "Asia/Kuala_Lumpur"
    field :country_code, :string, default: "MY"
    field :holiday_region, :string, default: "KUL"
    field :plan, :string, default: "free"
    field :seat_limit, :integer, default: 5
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :binary_id

    has_many :memberships, Tugas.Entities.Membership

    timestamps()
  end

  @doc false
  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:slug, :name, :timezone, :country_code, :holiday_region, :plan, :seat_limit])
    |> validate_required([:slug, :name])
    |> validate_number(:seat_limit, greater_than: 0)
    |> put_default_country_code()
    |> put_default_holiday_region()
    |> validate_inclusion(:country_code, Country.supported_codes())
    |> validate_holiday_region()
    |> unique_constraint(:slug)
  end

  defp put_default_country_code(changeset) do
    case get_field(changeset, :country_code) do
      nil ->
        timezone = get_field(changeset, :timezone) || "Asia/Kuala_Lumpur"
        put_change(changeset, :country_code, Country.default_for_timezone(timezone))

      _ ->
        changeset
    end
  end

  defp put_default_holiday_region(changeset) do
    case get_field(changeset, :country_code) do
      "MY" ->
        case get_field(changeset, :holiday_region) do
          nil ->
            timezone = get_field(changeset, :timezone) || "Asia/Kuala_Lumpur"
            put_change(changeset, :holiday_region, MalaysiaRegion.default_for_timezone(timezone))

          _ ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_holiday_region(changeset) do
    case get_field(changeset, :country_code) do
      "MY" ->
        validate_inclusion(changeset, :holiday_region, MalaysiaRegion.codes())

      _ ->
        changeset
    end
  end
end
