defmodule Tugas.Holidays.Registry do
  @moduledoc false

  alias Tugas.Holidays.Malaysia
  alias Tugas.Holidays.Nager

  @providers %{
    "MY" => Malaysia
  }

  @default_provider Nager

  def provider_for(country_code) when is_binary(country_code) do
    Map.get(@providers, String.upcase(country_code), @default_provider)
  end

  def fetch(country_code, year, region) do
    country_code
    |> provider_for()
    |> apply(:fetch, [country_code, year, region])
  end

  def uses_region?("MY"), do: true
  def uses_region?(_), do: false

  def plugin_country_codes, do: Map.keys(@providers)
end
