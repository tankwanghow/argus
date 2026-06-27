defmodule TugasWeb.DashboardLive.CalendarHelpers do
  @moduledoc false

  alias Tugas.Accounts.Scope
  alias Tugas.Duties
  alias TugasWeb.DutyLive.IndexHelpers, as: Index

  @max_chips_per_day 3

  def max_chips_per_day, do: @max_chips_per_day

  def month_range(year, month) do
    start = Date.new!(year, month, 1)
    last_day = Date.days_in_month(start)
    {start, Date.new!(year, month, last_day)}
  end

  def build_month_grid(year, month, today) do
    {month_start, month_end} = month_range(year, month)
    grid_start = start_of_week(month_start)
    grid_end = end_of_week(month_end)

    weeks =
      Date.range(grid_start, grid_end)
      |> Enum.chunk_every(7)
      |> Enum.map(fn week ->
        Enum.map(week, fn date ->
          %{
            date: date,
            in_month?: date.month == month,
            today?: Date.compare(date, today) == :eq
          }
        end)
      end)

    %{year: year, month: month, weeks: weeks}
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
    Calendar.strftime(dt, "%B %Y")
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
    Date.add(date, -dow)
  end

  defp end_of_week(date) do
    dow = Date.day_of_week(date, :sunday)
    Date.add(date, 6 - dow)
  end
end