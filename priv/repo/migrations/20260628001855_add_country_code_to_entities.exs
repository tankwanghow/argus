defmodule Tugas.Repo.Migrations.AddCountryCodeToEntities do
  use Ecto.Migration

  def change do
    alter table(:entities) do
      add :country_code, :string, null: false, default: "MY"
    end
  end
end
