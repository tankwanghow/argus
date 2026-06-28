defmodule Tugas.Holidays.Ics do
  @moduledoc false

  @event_marker "BEGIN:VEVENT"

  def fetch_year(url, year) when is_binary(url) and is_integer(year) do
    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        parse(body, year)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def parse(ics, year) when is_binary(ics) and is_integer(year) do
    ics
    |> String.split(@event_marker, trim: true)
    |> Enum.flat_map(&parse_event(&1, year))
    |> Enum.sort_by(& &1.date, Date)
  end

  defp parse_event(chunk, year) do
    with {:ok, date} <- event_date(chunk, year),
         name when is_binary(name) and name != "" <- event_name(chunk) do
      [%{date: date, name: name, local_name: name}]
    else
      _ -> []
    end
  end

  defp event_date(chunk, year) do
    case Regex.run(~r/DTSTART;VALUE=DATE:(\d{4})(\d{2})(\d{2})/, chunk) do
      [_, y, m, d] ->
        with {y, ""} <- Integer.parse(y),
             {m, ""} <- Integer.parse(m),
             {d, ""} <- Integer.parse(d),
             {:ok, date} <- Date.new(y, m, d),
             true <- date.year == year do
          {:ok, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp event_name(chunk) do
    case Regex.run(~r/^SUMMARY:(.+)$/m, chunk) do
      [_, name] -> String.trim(name)
      _ -> nil
    end
  end
end
