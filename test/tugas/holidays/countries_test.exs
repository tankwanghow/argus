defmodule Tugas.Holidays.CountriesTest do
  use ExUnit.Case, async: true

  alias Tugas.Holidays.Countries

  setup do
    Countries.init()
    Countries.clear()

    Application.put_env(:tugas, :nager_countries_fetcher, fn ->
      [
        %{code: "SG", name: "Singapore"},
        %{code: "JP", name: "Japan"},
        %{code: "GB", name: "United Kingdom"},
        %{code: "US", name: "United States"},
        %{code: "DE", name: "Germany"}
      ]
    end)

    on_exit(fn ->
      Application.delete_env(:tugas, :nager_countries_fetcher)
      Countries.clear()
    end)

    :ok
  end

  test "includes Malaysia plus seeded Nager countries" do
    codes = Countries.codes()

    assert "MY" in codes
    assert "SG" in codes
    assert "DE" in codes
    assert length(codes) >= 151
  end

  test "lists Malaysia first in options" do
    assert {"Malaysia", "MY"} = hd(Countries.options())
  end

  test "valid?/1 accepts known codes and rejects unknown codes" do
    assert Countries.valid?("SG")
    assert Countries.valid?("my")
    refute Countries.valid?("ZZ")
    refute Countries.valid?(nil)
  end

  test "all/0 does not call the live fetcher" do
    counter = :counters.new(1, [])

    Application.put_env(:tugas, :nager_countries_fetcher, fn ->
      :counters.add(counter, 1, 1)
      []
    end)

    Countries.clear()
    assert "SG" in Countries.codes()
    assert "US" in Countries.codes()
    assert :counters.get(counter, 1) == 0
  end

  test "refresh_from_nager/0 caches a successful live refresh" do
    counter = :counters.new(1, [])

    Application.put_env(:tugas, :nager_countries_fetcher, fn ->
      :counters.add(counter, 1, 1)

      for idx <- 1..10 do
        %{code: "C#{idx}", name: "Country #{idx}"}
      end ++ [%{code: "SG", name: "Singapore Updated"}]
    end)

    Countries.clear()
    assert :ok = Countries.refresh_from_nager()
    assert :counters.get(counter, 1) == 1

    assert {"Singapore Updated", "SG"} in Countries.options()
    Countries.refresh_from_nager()
    assert :counters.get(counter, 1) == 2
  end

  test "refresh_from_nager/0 ignores a degraded live response" do
    Application.put_env(:tugas, :nager_countries_fetcher, fn -> [] end)

    Countries.clear()
    assert :error = Countries.refresh_from_nager()
    assert length(Countries.codes()) > 1
  end
end
