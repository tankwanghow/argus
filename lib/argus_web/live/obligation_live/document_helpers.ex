defmodule ArgusWeb.ObligationLive.DocumentHelpers do
  @moduledoc false

  @uploadable_statuses ~w(open in_progress)

  @doc """
  Returns the best timeline event for attaching documents (in_progress preferred, then open).
  """
  def upload_event(events) when is_list(events) do
    events
    |> Enum.filter(&(&1.status in @uploadable_statuses))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> pick_upload_event()
  end

  defp pick_upload_event([]), do: nil

  defp pick_upload_event(events) do
    Enum.find_value(~w(in_progress open), fn status ->
      events
      |> Enum.filter(&(&1.status == status))
      |> List.last()
    end)
  end
end
