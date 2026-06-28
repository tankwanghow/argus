defmodule TugasWeb.DashboardLive.CalendarHelpers do
  @moduledoc false

  alias Tugas.Accounts.Scope
  alias Tugas.Duties
  alias Tugas.Holidays
  alias TugasWeb.DutyLive.IndexHelpers, as: Index

  @max_chips_per_day 3
  @max_someday_chips 10

  def max_chips_per_day, do: @max_chips_per_day
  def max_chips_per_day(:mobile), do: 2
  def max_chips_per_day(:desktop), do: @max_chips_per_day
  def max_chips_per_day(_), do: @max_chips_per_day

  def max_someday_chips, do: @max_someday_chips
  def max_someday_chips(:mobile), do: 6
  def max_someday_chips(:desktop), do: @max_someday_chips
  def max_someday_chips(_), do: @max_someday_chips

  def month_range(year, month) do
    start = Date.new!(year, month, 1)
    last_day = Date.days_in_month(start)
    {start, Date.new!(year, month, last_day)}
  end

  def build_month_grid(year, month, today) do
    {grid_start, grid_end} = grid_date_bounds(year, month)

    weeks =
      Date.range(grid_start, grid_end)
      |> Enum.chunk_every(7)
      |> Enum.map(fn week ->
        Enum.map(week, fn date ->
          %{
            date: date,
            in_month?: date.month == month,
            today?: Date.compare(date, today) == :eq,
            holidays: []
          }
        end)
      end)

    %{year: year, month: month, weeks: weeks}
  end

  def grid_date_bounds(year, month) do
    {month_start, month_end} = month_range(year, month)
    {start_of_week(month_start), end_of_week(month_end)}
  end

  def load_holidays_by_date(%Scope{} = scope, year, month) do
    {grid_start, grid_end} = grid_date_bounds(year, month)
    locale = scope.user.locale || "en"

    Holidays.list_for_range(scope.entity, grid_start, grid_end)
    |> Enum.map(fn holiday ->
      Map.put(holiday, :label, Holidays.label(holiday, locale))
    end)
    |> Holidays.group_by_date()
  end

  def annotate_holidays(%{weeks: weeks} = grid, holidays_by_date) do
    weeks =
      Enum.map(weeks, fn week ->
        Enum.map(week, fn cell ->
          holidays = Map.get(holidays_by_date, cell.date, [])
          %{cell | holidays: holidays}
        end)
      end)

    %{grid | weeks: weeks}
  end

  def group_by_date(rows) do
    Enum.group_by(rows, fn %{duty: duty} -> duty.due_by end)
  end

  def load_month_rows(%Scope{} = scope, today, mine?, year, month) do
    {month_start, month_end} = month_range(year, month)
    status = Index.status_atom(mine?, :live)

    duties =
      case Duties.list_duties(scope,
             status: status,
             due_after: Date.add(month_start, -1),
             due_before: month_end
           ) do
        :not_authorise -> []
        list -> list
      end

    Index.build_rows(duties, today)
    |> Enum.sort_by(fn %{duty: duty} -> {duty.due_by, String.downcase(duty.title)} end)
  end

  def load_someday_rows(%Scope{} = scope, today, mine?) do
    status = Index.status_atom(mine?, :live)

    duties =
      case Duties.list_duties(scope, status: status, dateless: true) do
        :not_authorise -> []
        list -> list
      end

    Index.build_rows(duties, today)
    |> Enum.sort_by(fn %{duty: duty} -> String.downcase(duty.title) end)
  end

  def month_label(year, month) do
    {:ok, dt} = Date.new(year, month, 1)
    Calendar.strftime(dt, "%b %Y")
  end

  def current_month(today), do: {today.year, today.month}

  def shift_month(year, month, delta) when delta == -1 do
    if month == 1, do: {year - 1, 12}, else: {year, month - 1}
  end

  def shift_month(year, month, delta) when delta == 1 do
    if month == 12, do: {year + 1, 1}, else: {year, month + 1}
  end

  defp start_of_week(date) do
    dow = Date.day_of_week(date, :sunday)
    Date.add(date, -(dow - 1))
  end

  defp end_of_week(date) do
    dow = Date.day_of_week(date, :sunday)
    Date.add(date, 7 - dow)
  end
end
