defmodule TugasWeb.DashboardLive.CalendarHelpersTest do
  use Tugas.DataCase, async: true

  alias TugasWeb.DashboardLive.CalendarHelpers

  test "build_month_grid starts each week on Sunday" do
    grid = CalendarHelpers.build_month_grid(2026, 6, ~D[2026-06-15])

    first_week =
      grid.weeks
      |> List.first()

    assert hd(first_week).date == ~D[2026-05-31]
    assert Date.day_of_week(hd(first_week).date, :sunday) == 1
  end

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

    assert today_cells == [
             %{date: ~D[2026-06-15], in_month?: true, today?: true, holidays: []}
           ]

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

  test "annotate_holidays adds holiday labels to matching cells" do
    grid = CalendarHelpers.build_month_grid(2026, 8, ~D[2026-08-15])

    holidays_by_date = %{
      ~D[2026-08-31] => [%{date: ~D[2026-08-31], label: "Hari Merdeka"}]
    }

    grid = CalendarHelpers.annotate_holidays(grid, holidays_by_date)

    cell =
      grid.weeks
      |> List.flatten()
      |> Enum.find(&(&1.date == ~D[2026-08-31]))

    assert cell.holidays == [%{date: ~D[2026-08-31], label: "Hari Merdeka"}]
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

  describe "load_urgent_rows/3" do
    import Tugas.DutiesFixtures
    alias Tugas.Duties
    alias Tugas.Duties.Urgency

    test "includes overdue + due-soon ranked, excludes ok and dateless" do
      scope = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(scope.entity, reminder_offsets: "7")
      today = Urgency.today_for(scope.entity.timezone)

      {:ok, overdue} =
        Duties.create_duty(scope, %{
          title: "Overdue",
          duty_type_id: type.id,
          due_by: Date.add(today, -2),
          open_note: "n"
        })

      {:ok, due_soon} =
        Duties.create_duty(scope, %{
          title: "Due soon",
          duty_type_id: type.id,
          due_by: Date.add(today, 3),
          open_note: "n"
        })

      {:ok, _ok} =
        Duties.create_duty(scope, %{
          title: "Not soon",
          duty_type_id: type.id,
          due_by: Date.add(today, 60),
          open_note: "n"
        })

      {:ok, _someday} =
        Duties.create_duty(scope, %{
          title: "Someday",
          duty_type_id: type.id,
          someday: true,
          open_note: "n"
        })

      rows = CalendarHelpers.load_urgent_rows(scope, today, false)

      assert Enum.map(rows, & &1.duty.id) == [overdue.id, due_soon.id]
    end
  end
end
