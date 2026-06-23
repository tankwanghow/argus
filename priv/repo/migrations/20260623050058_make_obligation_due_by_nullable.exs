defmodule Argus.Repo.Migrations.MakeObligationDueByNullable do
  use Ecto.Migration

  def change do
    alter table(:obligations) do
      modify :due_by, :date, null: true, from: {:date, null: false}
    end
  end
end
