defmodule Tugas.Holidays.WarmCache do
  @moduledoc false
  use GenServer

  require Logger

  alias Tugas.Entities.MalaysiaRegion
  alias Tugas.Holidays
  alias Tugas.Holidays.Countries

  @concurrency 8

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), :warm)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:warm, state) do
    run()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:ensure_year, country_code, year, region}, state) do
    warm_year(country_code, year, region)
    {:noreply, state}
  end

  def run(opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    if force? or enabled?() do
      Logger.info("[tugas] Public holiday cache warm started")
      Tugas.Holidays.Store.clear()
      _ = Countries.refresh_from_nager()

      try do
        countries = warm_countries()
        years = warm_years()
        total = warm_jobs(countries, years)

        Logger.info(
          "[tugas] Warming holiday cache for #{length(countries)} countries, years #{inspect(years)} (#{total} fetches)…"
        )

        countries
        |> Enum.map(fn %{code: code} -> code end)
        |> Task.async_stream(
          fn code -> warm_country(code, years) end,
          max_concurrency: @concurrency,
          timeout: :infinity,
          ordered: false
        )
        |> Stream.run()

        Logger.info("[tugas] Public holiday cache warm complete")
      rescue
        error ->
          Logger.error("[tugas] Public holiday cache warm failed: #{Exception.message(error)}")
      end
    end

    :ok
  end

  def ensure_year(country_code, year, region) do
    case Process.whereis(__MODULE__) do
      nil ->
        Task.start(fn -> Holidays.fetch_and_store(country_code, year, region) end)

      pid ->
        GenServer.cast(pid, {:ensure_year, country_code, year, region})
    end

    :ok
  end

  defp warm_country("MY", years) do
    Enum.each(years, fn year ->
      Enum.each(MalaysiaRegion.codes(), fn region ->
        warm_year("MY", year, region)
      end)
    end)
  end

  defp warm_country(country_code, years) do
    Enum.each(years, fn year ->
      warm_year(country_code, year, nil)
    end)
  end

  defp warm_year(country_code, year, region) do
    Holidays.fetch_and_store(country_code, year, region)
  end

  defp warm_countries do
    Application.get_env(:tugas, :holiday_warm_countries, Countries.all())
  end

  defp warm_years do
    year = Date.utc_today().year
    [year - 1, year, year + 1]
  end

  defp warm_jobs(countries, years) do
    Enum.reduce(countries, 0, fn %{code: code}, acc ->
      acc + length(years) * job_count(code)
    end)
  end

  defp job_count("MY"), do: length(MalaysiaRegion.codes())
  defp job_count(_), do: 1

  defp enabled?, do: Application.get_env(:tugas, :warm_holiday_cache, false)
end
