defmodule Tugas.Holidays do
  @moduledoc """
  Public holidays for entity jurisdictions.

  Country coverage comes from Nager.Date (~151 countries) plus Malaysia via a
  state-aware plugin (Nager does not publish MY data).
  """

  alias Tugas.Entities.Country
  alias Tugas.Entities.Entity
  alias Tugas.Entities.MalaysiaRegion
  alias Tugas.Holidays.Registry
  alias Tugas.Holidays.Store
  alias Tugas.Holidays.WarmCache

  def list_for_range(%Entity{} = entity, %Date{} = start_date, %Date{} = end_date) do
    list_for_range(entity.country_code, start_date, end_date, entity.holiday_region)
  end

  def list_for_range(country_code, %Date{} = start_date, %Date{} = end_date) do
    list_for_range(country_code, start_date, end_date, nil)
  end

  def list_for_range(country_code, %Date{} = start_date, %Date{} = end_date, holiday_region) do
    country_code =
      country_code
      |> case do
        code when is_binary(code) -> code
        _ -> ""
      end
      |> String.trim()
      |> String.upcase()

    if country_code != "" and Country.valid?(country_code) do
      region = normalize_region(country_code, holiday_region)

      start_date
      |> years_for_range(end_date)
      |> Enum.flat_map(&fetch_year(country_code, &1, region))
      |> Enum.filter(fn %{date: date} ->
        Date.compare(date, start_date) != :lt and Date.compare(date, end_date) != :gt
      end)
      |> Enum.sort_by(& &1.date, Date)
    else
      []
    end
  end

  def list_for_range(_country_code, _start_date, _end_date, _holiday_region), do: []

  def group_by_date(holidays) do
    Enum.group_by(holidays, & &1.date)
  end

  def display_name(%{local_name: local, name: name}, locale) when locale in ~w(ms zh) do
    local || name || ""
  end

  def display_name(%{name: name, local_name: local}, _locale) do
    name || local || ""
  end

  def label(holiday, locale), do: display_name(holiday, locale)

  def fetch_and_store(country_code, year, region) do
    cache_key = {country_code, year, region || ""}

    if Store.get(cache_key) == :miss do
      holidays = do_fetch_year(country_code, year, region)
      if holidays != [], do: Store.put(cache_key, holidays)
    end

    :ok
  end

  defp normalize_region(country_code, region) do
    if Registry.uses_region?(country_code) do
      case region do
        r when is_binary(r) and r != "" ->
          if MalaysiaRegion.valid?(r), do: r, else: "KUL"

        _ ->
          "KUL"
      end
    else
      nil
    end
  end

  defp years_for_range(%Date{year: y}, %Date{year: y}), do: [y]

  defp years_for_range(%Date{year: start_year}, %Date{year: end_year})
       when start_year <= end_year do
    Enum.to_list(start_year..end_year)
  end

  defp fetch_year(country_code, year, region) do
    cache_key = {country_code, year, region || ""}

    case Application.get_env(:tugas, :holidays_fetcher) do
      fetcher when is_function(fetcher, 3) ->
        fetcher.(country_code, year, region)

      _ ->
        case Store.get(cache_key) do
          holidays when is_list(holidays) ->
            holidays

          :miss ->
            WarmCache.ensure_year(country_code, year, region)
            []
        end
    end
  end

  defp do_fetch_year(country_code, year, region) do
    holidays_fetcher().(country_code, year, region)
  rescue
    _ -> []
  end

  defp holidays_fetcher do
    Application.get_env(:tugas, :holidays_fetcher) ||
      Application.get_env(:tugas, :holidays_registry_fetcher, &Registry.fetch/3)
  end
end
