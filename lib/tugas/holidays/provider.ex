defmodule Tugas.Holidays.Provider do
  @moduledoc false

  @type holiday :: %{
          date: Date.t(),
          name: String.t() | nil,
          local_name: String.t() | nil
        }

  @callback fetch(country_code :: String.t(), year :: integer(), region :: String.t() | nil) ::
              [holiday]
end
