defmodule Tugas.Repo.Migrations.MakeDutyDueByNullable do
  use Ecto.Migration

  def change do
    alter table(:duties) do
      modify :due_by, :date, null: true, from: {:date, null: false}
    end
  end
end
