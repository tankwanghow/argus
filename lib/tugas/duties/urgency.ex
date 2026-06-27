defmodule Tugas.Duties.Urgency do
  @moduledoc """
  Dashboard urgency classification for duties.
  """

  alias Tugas.Duties.Type

  @type urgency :: :overdue | :due_soon | :ok | :none
  @type tier :: :overdue | :critical | :due_soon | :approaching | :ok | :none

  @spec classify(Type.t(), Date.t() | nil, Date.t()) :: urgency()
  def classify(%Type{}, nil, _today), do: :none

  def classify(%Type{reminder_offsets: offsets}, due_by, today) do
    cond do
      Date.compare(due_by, today) == :lt -> :overdue
      due_soon?(offsets, due_by, today) -> :due_soon
      true -> :ok
    end
  end

  @doc """
  Graded urgency for color-coding a card's accent border.

  The span between the smallest and largest reminder offset is divided into
  three equal bands (critical → due_soon → approaching). A single offset is
  widened by 7 days so it still yields three bands. `:overdue` (past due) and
  `:ok` (beyond the largest offset) are fixed endpoints.
  """
  @spec tier(Type.t(), Date.t() | nil, Date.t()) :: tier()
  def tier(%Type{}, nil, _today), do: :none

  def tier(%Type{reminder_offsets: offsets}, due_by, today) do
    days = Date.diff(due_by, today)
    {min, max} = tier_bounds(offsets)
    step = (max - min) / 3

    cond do
      days < 0 -> :overdue
      days > max -> :ok
      days <= min + step -> :critical
      days <= min + 2 * step -> :due_soon
      true -> :approaching
    end
  end

  defp tier_bounds(offsets) do
    parsed = offsets |> parse_offsets() |> Enum.sort()
    min = List.first(parsed)
    max = List.last(parsed)
    if max > min, do: {min, max}, else: {min, min + 7}
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
