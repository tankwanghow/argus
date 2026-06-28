defmodule Tugas.Holidays.MalaysiaTest do
  use ExUnit.Case, async: true

  alias Tugas.Holidays.Malaysia

  @tag :external_api
  test "falls back to ICS when the Malaysia API is unavailable" do
    holidays = Malaysia.fetch("MY", 2026, "KUL")

    assert holidays != []
    assert Enum.any?(holidays, &(&1.date == ~D[2026-06-01]))
  end
end
