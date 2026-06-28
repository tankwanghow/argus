defmodule Tugas.Holidays.WarmCacheTest do
  use ExUnit.Case, async: false

  alias Tugas.Holidays.Countries
  alias Tugas.Holidays.Store
  alias Tugas.Holidays.WarmCache

  setup do
    _ = stop_warm_cache()

    Store.init()
    Store.clear()
    Countries.init()
    Countries.clear()

    Application.put_env(:tugas, :warm_holiday_cache, true)

    counter = :counters.new(1, [])

    Application.put_env(:tugas, :nager_countries_fetcher, fn ->
      [%{code: "SG", name: "Singapore"}, %{code: "US", name: "United States"}]
    end)

    Application.put_env(:tugas, :holidays_fetcher, fn country, year, region ->
      :counters.add(counter, 1, 1)

      [
        %{
          date: Date.new!(year, 1, 1),
          name: "#{country}-#{year}",
          local_name: nil,
          region: region
        }
      ]
    end)

    on_exit(fn ->
      _ = stop_warm_cache()
      Application.delete_env(:tugas, :warm_holiday_cache)
      Application.delete_env(:tugas, :nager_countries_fetcher)
      Application.delete_env(:tugas, :holidays_fetcher)
      Store.clear()
      Countries.clear()
    end)

    {:ok, counter: counter}
  end

  test "fetches holidays for all countries and both warm years", %{counter: counter} do
    WarmCache.run()

    # MY, SG, US × 2 years; MY fetches every state/territory per year
    assert :counters.get(counter, 1) == 36
  end

  test "no-ops when disabled" do
    Application.put_env(:tugas, :warm_holiday_cache, false)

    assert :ok = WarmCache.run()
  end

  test "force option runs even when disabled" do
    Application.put_env(:tugas, :warm_holiday_cache, false)

    assert :ok = WarmCache.run(force: true)
  end

  defp stop_warm_cache do
    case Process.whereis(WarmCache) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end
  rescue
    _ -> :ok
  end
end
