defmodule Argus.Obligations.Completion do
  @moduledoc """
  Done validation against obligation snapshots and cycle documents.
  """

  alias Argus.Obligations.Obligation

  def validate_done_requirements(%Obligation{} = obligation, done_attrs, cycle_documents) do
    note = Map.get(done_attrs, :note) || Map.get(done_attrs, "note")

    with :ok <- validate_note(note),
         :ok <- validate_document_slots(obligation, cycle_documents) do
      :ok
    end
  end

  defp validate_note(note) when note in [nil, ""], do: {:error, :note_required}
  defp validate_note(_), do: :ok

  defp validate_document_slots(%Obligation{complete_documents: ""}, _cycle_documents), do: :ok

  defp validate_document_slots(
         %Obligation{complete_documents: complete_documents},
         cycle_documents
       ) do
    required = parse_csv(complete_documents)

    slots =
      cycle_documents
      |> Enum.reject(& &1.voided_at)
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
