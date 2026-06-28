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

  test "includes Malaysia plus Nager countries" do
    codes = Countries.codes()

    assert "MY" in codes
    assert "SG" in codes
    assert "DE" in codes
    assert length(codes) == 6
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

  test "caches the country list" do
    counter = :counters.new(1, [])

    Application.put_env(:tugas, :nager_countries_fetcher, fn ->
      :counters.add(counter, 1, 1)
      [%{code: "SG", name: "Singapore"}]
    end)

    Countries.clear()
    Countries.all()
    Countries.all()

    assert :counters.get(counter, 1) == 1
  end
end
