defmodule Tugas.Holidays.Countries do
  @moduledoc false

  alias Tugas.Holidays.Nager

  @table :tugas_holiday_countries
  @cache_key :all
  @my_country %{code: "MY", name: "Malaysia"}
  @favorite_codes ~w(MY SG JP GB US AU)
  @min_live_countries 10
  @static_json "holidays/nager_countries.json"

  def init, do: ensure_table!()

  def all do
    ensure_table!()

    case :ets.lookup(@table, @cache_key) do
      [{@cache_key, countries}] ->
        countries

      [] ->
        static_countries()
    end
  end

  def codes, do: Enum.map(all(), & &1.code)

  def options do
    all()
    |> Enum.map(fn %{name: name, code: code} -> {name, code} end)
  end

  def valid?(code) when is_binary(code), do: String.upcase(code) in codes()
  def valid?(_), do: false

  def refresh_from_nager do
    ensure_table!()

    case countries_fetcher().() do
      list when is_list(list) and length(list) >= @min_live_countries ->
        countries =
          ([@my_country] ++ list)
          |> Enum.uniq_by(& &1.code)
          |> prioritize_favorites()
          |> Enum.sort_by(fn %{name: name, code: code} ->
            {favorite_rank(code), String.downcase(name)}
          end)

        :ets.insert(@table, {@cache_key, countries})
        :ok

      _ ->
        :error
    end
  end

  def clear do
    if table?(), do: :ets.delete(@table, @cache_key)
    :ok
  end

  defp static_countries do
    ([@my_country] ++ load_static_nager_countries())
    |> Enum.uniq_by(& &1.code)
    |> prioritize_favorites()
    |> Enum.sort_by(fn %{name: name, code: code} ->
      {favorite_rank(code), String.downcase(name)}
    end)
  end

  defp load_static_nager_countries do
    path = Path.join(:code.priv_dir(:tugas), @static_json)

    with {:ok, body} <- File.read(path),
         {:ok, rows} <- Jason.decode(body) do
      Enum.map(rows, fn %{"countryCode" => code, "name" => name} ->
        %{code: code, name: name}
      end)
    else
      _ -> []
    end
  end

  defp countries_fetcher do
    Application.get_env(:tugas, :nager_countries_fetcher, &Nager.list_available_countries/0)
  end

  defp prioritize_favorites(countries) do
    favorites = Enum.filter(countries, &(&1.code in @favorite_codes))
    rest = Enum.reject(countries, &(&1.code in @favorite_codes))
    favorites ++ rest
  end

  defp favorite_rank(code) do
    case Enum.find_index(@favorite_codes, &(&1 == code)) do
      nil -> 100
      idx -> idx
    end
  end

  defp ensure_table! do
    if table?() do
      :ok
    else
      try do
        :ets.new(@table, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp table?, do: :ets.whereis(@table) != :undefined
end
