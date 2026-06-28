defmodule Tugas.Holidays.IcsTest do
  use ExUnit.Case, async: true

  alias Tugas.Holidays.Ics

  @sample_ics """
  BEGIN:VCALENDAR
  BEGIN:VEVENT
  DTSTART;VALUE=DATE:20260601
  DTEND;VALUE=DATE:20260602
  SUMMARY:Yang di-Pertuan Agong's Birthday
  END:VEVENT
  BEGIN:VEVENT
  DTSTART;VALUE=DATE:20260617
  SUMMARY:Awal Muharram
  END:VEVENT
  BEGIN:VEVENT
  DTSTART;VALUE=DATE:20270101
  SUMMARY:Other year
  END:VEVENT
  END:VCALENDAR
  """

  test "parse/2 returns holidays for the requested year only" do
    holidays = Ics.parse(@sample_ics, 2026)

    assert length(holidays) == 2
    assert Enum.any?(holidays, &(&1.date == ~D[2026-06-01]))
    assert Enum.any?(holidays, &(&1.date == ~D[2026-06-17]))
  end
end
