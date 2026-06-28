defmodule Tugas.Holidays.RegistryTest do
  use ExUnit.Case, async: true

  alias Tugas.Holidays.Malaysia
  alias Tugas.Holidays.Nager
  alias Tugas.Holidays.Registry

  test "routes Malaysia to the Malaysia provider" do
    assert Registry.provider_for("MY") == Malaysia
    assert Registry.provider_for("my") == Malaysia
  end

  test "routes other countries to Nager" do
    assert Registry.provider_for("SG") == Nager
    assert Registry.provider_for("US") == Nager
  end

  test "only Malaysia uses holiday regions" do
    assert Registry.uses_region?("MY")
    refute Registry.uses_region?("SG")
  end
end
