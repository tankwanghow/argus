defmodule Mix.Tasks.Tugas.WarmHolidays do
  @shortdoc "Pre-fetch public holidays into the ETS cache"

  @moduledoc """
  Downloads public holidays for all supported countries into the ETS cache.

      mix tugas.warm_holidays

  Useful after a code reload when `mix phx.server` was not fully restarted.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Tugas.Holidays.WarmCache.run(force: true)
  end
end
