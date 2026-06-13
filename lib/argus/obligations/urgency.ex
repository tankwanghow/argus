defmodule Argus.Obligations.Urgency do
  @moduledoc """
  Dashboard urgency classification for obligations.
  """

  alias Argus.Obligations.Type

  @type urgency :: :overdue | :due_soon | :ok

  @spec classify(Type.t(), Date.t(), Date.t()) :: urgency()
  def classify(%Type{reminder_offsets: offsets}, due_by, today) do
    cond do
      Date.compare(due_by, today) == :lt -> :overdue
      due_soon?(offsets, due_by, today) -> :due_soon
      true -> :ok
    end
  end

  @spec today_for(String.t()) :: Date.t()
  def today_for(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end

  defp due_soon?(offsets, due_by, today) do
    days = Date.diff(due_by, today)

    offsets
    |> parse_offsets()
    |> Enum.any?(fn offset -> days <= offset end)
  end

  def parse_offsets(nil), do: [7]

  def parse_offsets(str) do
    parsed =
      str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(fn tok ->
        case Integer.parse(tok) do
          {n, ""} when n >= 0 -> [n]
          _ -> []
        end
      end)

    if parsed == [], do: [7], else: parsed
  end
end