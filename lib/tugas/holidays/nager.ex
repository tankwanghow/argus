defmodule Tugas.Holidays.Nager do
  @moduledoc false

  @behaviour Tugas.Holidays.Provider

  @api_base "https://date.nager.at/api/v3"
  @countries_url "#{@api_base}/AvailableCountries"

  @impl true
  def fetch(country_code, year, _region) do
    url = "#{@api_base}/PublicHolidays/#{year}/#{country_code}"

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        Enum.map(body, &parse_holiday/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def list_available_countries do
    case Req.get(@countries_url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        Enum.map(body, fn %{"countryCode" => code, "name" => name} ->
          %{code: code, name: name}
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp parse_holiday(%{"date" => iso} = row) do
    {:ok, date} = Date.from_iso8601(iso)

    %{
      date: date,
      name: Map.get(row, "name"),
      local_name: Map.get(row, "localName")
    }
  end
end
