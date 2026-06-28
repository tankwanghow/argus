defmodule Tugas.HolidaysTest do
  use ExUnit.Case, async: true

  alias Tugas.Entities.Entity
  alias Tugas.Holidays
  alias Tugas.Holidays.Store

  setup do
    stop_warm_cache()
    Store.init()
    Store.clear()
    :ok
  end

  describe "list_for_range/3" do
    test "returns holidays within the date range" do
      stub_fetcher(fn _country, _year, _region ->
        [
          %{date: ~D[2026-08-30], name: "Day before", local_name: "Eve"},
          %{date: ~D[2026-08-31], name: "Independence Day", local_name: "Hari Merdeka"},
          %{date: ~D[2026-09-01], name: "Outside", local_name: "Outside"}
        ]
      end)

      holidays = Holidays.list_for_range("MY", ~D[2026-08-01], ~D[2026-08-31])

      assert length(holidays) == 2
      assert Enum.at(holidays, 0).date == ~D[2026-08-30]
      assert Enum.at(holidays, 1).date == ~D[2026-08-31]
    end

    test "passes holiday region for Malaysia entities" do
      stub_fetcher(fn country, _year, region ->
        assert country == "MY"
        assert region == "SGR"

        [%{date: ~D[2026-08-31], name: "Hari Merdeka", local_name: "Hari Merdeka"}]
      end)

      entity = %Entity{country_code: "MY", holiday_region: "SGR"}

      assert [%{date: ~D[2026-08-31]}] =
               Holidays.list_for_range(entity, ~D[2026-08-01], ~D[2026-08-31])
    end

    test "bypasses cache while a test fetcher is configured" do
      counter = :counters.new(1, [])

      stub_fetcher(fn country, _year, _region ->
        :counters.add(counter, 1, 1)

        [%{date: ~D[2026-08-31], name: "#{country} holiday", local_name: nil}]
      end)

      Holidays.list_for_range("SG", ~D[2026-08-01], ~D[2026-08-31])
      Holidays.list_for_range("SG", ~D[2026-09-01], ~D[2026-09-30])

      assert :counters.get(counter, 1) == 2
    end

    test "returns empty list for unsupported country codes" do
      assert Holidays.list_for_range("ZZ", ~D[2026-08-01], ~D[2026-08-31]) == []
      assert Holidays.list_for_range(nil, ~D[2026-08-01], ~D[2026-08-31]) == []
    end
  end

  describe "Store" do
    test "caches holiday lists per cache key" do
      holidays = [%{date: ~D[2026-08-31], name: "Hari Merdeka", local_name: "Hari Merdeka"}]
      key = {"MY", 2026, "KUL"}

      Store.put(key, holidays)

      assert Store.get(key) == holidays
      assert Store.get({"MY", 2026, "SGR"}) == :miss
    end

    test "does not persist empty holiday lists" do
      stub_fetcher(fn _country, _year, _region -> [] end)

      assert Holidays.list_for_range("SG", ~D[2026-01-01], ~D[2026-12-31]) == []
      assert Store.get({"SG", 2026, ""}) == :miss
    end

    test "returns immediately on cache miss without blocking on the default fetcher" do
      Application.delete_env(:tugas, :holidays_fetcher)

      parent = self()

      Application.put_env(:tugas, :holidays_registry_fetcher, fn country, year, region ->
        send(parent, {:fetch_started, country, year, region})
        Process.sleep(5_000)
        [%{date: Date.new!(year, 1, 1), name: "Late", local_name: nil}]
      end)

      on_exit(fn ->
        Application.delete_env(:tugas, :holidays_registry_fetcher)
      end)

      assert Holidays.list_for_range("SG", ~D[2026-01-01], ~D[2026-01-31]) == []
      assert_receive {:fetch_started, "SG", 2026, nil}, 1_000
    end
  end

  describe "display_name/2" do
    test "prefers local name for ms and zh locales" do
      holiday = %{name: "Independence Day", local_name: "Hari Merdeka"}

      assert Holidays.display_name(holiday, "ms") == "Hari Merdeka"
      assert Holidays.display_name(holiday, "zh") == "Hari Merdeka"
      assert Holidays.display_name(holiday, "en") == "Independence Day"
    end
  end

  defp stub_fetcher(fun) do
    Application.put_env(:tugas, :holidays_fetcher, fun)

    on_exit(fn ->
      Application.delete_env(:tugas, :holidays_fetcher)
    end)
  end

  defp stop_warm_cache do
    case Process.whereis(Tugas.Holidays.WarmCache) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end
  rescue
    _ -> :ok
  end
end
