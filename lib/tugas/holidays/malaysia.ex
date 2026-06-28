defmodule Tugas.Holidays.Malaysia do
  @moduledoc false

  @behaviour Tugas.Holidays.Provider

  alias Tugas.Holidays.Ics

  @api_base "https://malaysia-holiday.dydxsoft.my/api/v1/holidays"

  @ics_url "https://calendar.google.com/calendar/ical/en.malaysia%23holiday%40group.v.calendar.google.com/public/basic.ics"

  @impl true
  def fetch("MY", year, region) when is_binary(region) do
    case fetch_from_api(year, region) do
      [_ | _] = holidays ->
        holidays

      _ ->
        fetch_from_ics(year)
    end
  end

  def fetch("MY", year, _region), do: fetch("MY", year, "KUL")
  def fetch(_country_code, _year, _region), do: []

  defp fetch_from_api(year, region) do
    url = "#{@api_base}?year=#{year}&state=#{region}"

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"data" => rows}}} when is_list(rows) ->
        Enum.map(rows, &parse_api_holiday/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp fetch_from_ics(year), do: Ics.fetch_year(@ics_url, year)

  defp parse_api_holiday(%{"date" => iso, "name" => name}) do
    {:ok, date} = Date.from_iso8601(iso)

    %{
      date: date,
      name: name,
      local_name: name
    }
  end
end
