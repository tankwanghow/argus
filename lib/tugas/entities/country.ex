defmodule Tugas.Entities.Country do
  @moduledoc false

  alias Tugas.Holidays.Countries

  def supported_codes, do: Countries.codes()

  def options, do: Countries.options()

  def valid?(code), do: Countries.valid?(code)

  def default_for_timezone("Asia/Kuala_Lumpur"), do: "MY"
  def default_for_timezone("Asia/Singapore"), do: "SG"
  def default_for_timezone("Asia/Tokyo"), do: "JP"
  def default_for_timezone("Europe/London"), do: "GB"
  def default_for_timezone("America/New_York"), do: "US"
  def default_for_timezone("Australia/Sydney"), do: "AU"
  def default_for_timezone(_), do: "MY"
end
