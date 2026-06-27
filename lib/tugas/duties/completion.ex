defmodule Tugas.Duties.Completion do
  @moduledoc """
  Done validation against duty snapshots and cycle documents.
  """

  alias Tugas.Duties.Duty

  def validate_done_requirements(%Duty{} = duty, done_attrs, cycle_documents) do
    note = Map.get(done_attrs, :note) || Map.get(done_attrs, "note")

    with :ok <- validate_note(note),
         :ok <- validate_document_slots(duty, cycle_documents) do
      :ok
    end
  end

  defp validate_note(note) when note in [nil, ""], do: {:error, :note_required}
  defp validate_note(_), do: :ok

  defp validate_document_slots(%Duty{complete_documents: ""}, _cycle_documents), do: :ok

  defp validate_document_slots(
         %Duty{complete_documents: complete_documents},
         cycle_documents
       ) do
    required = parse_csv(complete_documents)

    # Only the current required slots matter. Files tagged with old or extra slot
    # names are ignored — they do not satisfy requirements and do not block Done.
    slots =
      cycle_documents
      |> Enum.reject(& &1.voided_at)
      |> Enum.filter(&(&1.document_slot in required))
      |> Map.new(&{&1.document_slot, true})

    case Enum.find(required, &(not Map.has_key?(slots, &1))) do
      nil -> :ok
      missing -> {:error, {:missing_document, missing}}
    end
  end

  defp parse_csv(""), do: []

  defp parse_csv(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
