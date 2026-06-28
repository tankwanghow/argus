defmodule Tugas.Holidays.NagerTest do
  use ExUnit.Case, async: true

  alias Tugas.Holidays.Nager

  test "fetch/3 skips malformed rows and keeps valid holidays" do
    body = [
      %{"date" => "2026-01-01", "name" => "New Year", "localName" => "NY"},
      %{"date" => "2026-13-01", "name" => "Bad month"},
      %{"name" => "Missing date"},
      %{"date" => "2026-12-25", "name" => "Christmas", "localName" => "Xmas"}
    ]

    assert [
             %{date: ~D[2026-01-01], name: "New Year", local_name: "NY"},
             %{date: ~D[2026-12-25], name: "Christmas", local_name: "Xmas"}
           ] = Nager.parse_holidays(body)
  end
end
