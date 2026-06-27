defmodule Tugas.Duties.SampleTypes do
  @moduledoc """
  Default duty types inserted when a new entity is created.
  """

  alias Tugas.Duties.Type
  alias Tugas.Repo

  @samples [
    %{
      name: "EPF Monthly",
      recurring_interval: "monthly",
      complete_documents: "payment_receipt",
      reminder_offsets: "7,1"
    },
    %{
      name: "SOCSO Monthly",
      recurring_interval: "monthly",
      reminder_offsets: "7,1"
    },
    %{
      name: "SST Return",
      recurring_interval: "quarterly",
      reminder_offsets: "30,7,1"
    },
    %{
      name: "SSM Annual Return",
      recurring_interval: "annual",
      reminder_offsets: "30,7,1"
    },
    %{
      name: "LHDN Tax Estimation",
      recurring_interval: "custom",
      reminder_offsets: "30,7,1"
    }
  ]

  def samples, do: @samples

  def seed_for_entity(entity_id) when is_binary(entity_id) do
    now = DateTime.utc_now(:second)

    entries =
      Enum.map(@samples, fn attrs ->
        attrs
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:entity_id, entity_id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Type, entries, on_conflict: :nothing)
    :ok
  end
end
