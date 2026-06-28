defmodule Tugas.Entities.MalaysiaRegion do
  @moduledoc false

  @codes ~w(JHR KDH KTN MLK NSN PHG PRK PLS PNG SBH SWK SGR TRG KUL LBN PJY)

  def codes, do: @codes

  def options do
    [
      {"Wilayah Persekutuan Kuala Lumpur", "KUL"},
      {"Selangor", "SGR"},
      {"Johor", "JHR"},
      {"Kedah", "KDH"},
      {"Kelantan", "KTN"},
      {"Melaka", "MLK"},
      {"Negeri Sembilan", "NSN"},
      {"Pahang", "PHG"},
      {"Perak", "PRK"},
      {"Perlis", "PLS"},
      {"Pulau Pinang", "PNG"},
      {"Sabah", "SBH"},
      {"Sarawak", "SWK"},
      {"Terengganu", "TRG"},
      {"Wilayah Persekutuan Labuan", "LBN"},
      {"Wilayah Persekutuan Putrajaya", "PJY"}
    ]
  end

  def default_for_timezone("Asia/Kuala_Lumpur"), do: "KUL"
  def default_for_timezone("Asia/Singapore"), do: nil
  def default_for_timezone(_), do: "KUL"

  def valid?(code) when code in @codes, do: true
  def valid?(_), do: false
end
