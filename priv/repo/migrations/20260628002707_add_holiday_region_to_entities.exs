defmodule Tugas.Repo.Migrations.AddHolidayRegionToEntities do
  use Ecto.Migration

  def change do
    alter table(:entities) do
      add :holiday_region, :string, default: "KUL"
    end
  end
end
