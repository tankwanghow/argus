defmodule Tugas.Holidays.Countries do
  @moduledoc false

  alias Tugas.Holidays.Nager

  @table :tugas_holiday_countries
  @cache_key :all
  @my_country %{code: "MY", name: "Malaysia"}
  @favorite_codes ~w(MY SG JP GB US AU)

  def init, do: ensure_table!()

  def all do
    ensure_table!()

    case :ets.lookup(@table, @cache_key) do
      [{@cache_key, countries}] ->
        countries

      [] ->
        countries = load_countries()
        :ets.insert(@table, {@cache_key, countries})
        countries
    end
  end

  def codes, do: Enum.map(all(), & &1.code)

  def options do
    all()
    |> Enum.map(fn %{name: name, code: code} -> {name, code} end)
  end

  def valid?(code) when is_binary(code), do: String.upcase(code) in codes()
  def valid?(_), do: false

  def clear do
    if table?(), do: :ets.delete(@table, @cache_key)
    :ok
  end

  defp load_countries do
    nager_countries =
      case countries_fetcher().() do
        list when is_list(list) -> list
        _ -> []
      end

    ((@my_country |> List.wrap()) ++ nager_countries)
    |> Enum.uniq_by(& &1.code)
    |> prioritize_favorites()
    |> Enum.sort_by(fn %{name: name, code: code} ->
      {favorite_rank(code), String.downcase(name)}
    end)
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
