defmodule TugasWeb.DashboardLive.CalendarHelpersTest do
  use Tugas.DataCase, async: true

  alias TugasWeb.DashboardLive.CalendarHelpers

  test "build_month_grid includes leading/trailing days and marks today" do
    today = ~D[2026-06-15]
    grid = CalendarHelpers.build_month_grid(2026, 6, today)

    assert grid.year == 2026
    assert grid.month == 6
    assert length(grid.weeks) in 5..6

    today_cells =
      grid.weeks
      |> List.flatten()
      |> Enum.filter(& &1.today?)

    assert today_cells == [%{date: ~D[2026-06-15], in_month?: true, today?: true}]

    june_cells =
      grid.weeks
      |> List.flatten()
      |> Enum.filter(& &1.in_month?)
      |> Enum.map(& &1.date)

    assert ~D[2026-06-01] in june_cells
    assert ~D[2026-06-30] in june_cells
  end

  test "month_range returns first and last day of month" do
    assert CalendarHelpers.month_range(2026, 6) == {~D[2026-06-01], ~D[2026-06-30]}
  end

  test "group_by_date buckets rows by duty.due_by" do
    rows = [
      %{duty: %{id: "a", due_by: ~D[2026-06-10], title: "A"}},
      %{duty: %{id: "b", due_by: ~D[2026-06-10], title: "B"}},
      %{duty: %{id: "c", due_by: ~D[2026-06-11], title: "C"}}
    ]

    grouped = CalendarHelpers.group_by_date(rows)

    assert map_size(grouped) == 2
    assert length(grouped[~D[2026-06-10]]) == 2
    assert length(grouped[~D[2026-06-11]]) == 1
  end
end