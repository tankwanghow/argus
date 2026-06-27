# Desktop dashboard calendar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a desktop dashboard at `/entities/:slug` with a month calendar of live duties (urgency-colored, grouped by due date), a Someday strip for dateless live duties, and a compact todos sidebar — without changing `DutyLive.Index`.

**Architecture:** New `DashboardLive.Index` orchestrates mount/events; `DashboardLive.CalendarHelpers` builds the month grid and groups enriched duty rows; `DutyCalendar` and `DashboardTodosPanel` function components render the UI. Reuses `IndexHelpers.build_rows/2`, `UrgencyBadge`, and `DutiesFilter` for `mine?` only. Extends `Duties.list_duties/2` with SQL date bounds so the calendar never loads the full live set.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8.5 / LiveView 1.2.1 / Ecto 3.13 / PostgreSQL / Tailwind v4 + daisyUI 5.

**Spec:** `docs/superpowers/specs/2026-06-27-dashboard-calendar-design.md`.

## Global Constraints

- `DutyLive.Index` and `/entities/:slug/duties` are **unchanged**.
- Calendar shows **live duties only** (`:live` / `:my_live`).
- Urgency colors use existing `UrgencyBadge.tier_border/1` on duty chips.
- `today` is computed via `Urgency.today_for(entity.timezone)` — never `Date.utc_today()`.
- Every LiveView in `Layouts.app` / `Layouts.mobile_app` must define `handle_event("close_modal_on_escape", …)`.
- Unauthorized context calls return `:not_authorise`.
- Run `mix precommit` before declaring the feature done.
- TDD: failing test → implement → pass → commit per task.

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `lib/tugas/duties.ex` | `list_duties/2` date-bound + dateless SQL filters |
| Create | `lib/tugas_web/live/dashboard_live/calendar_helpers.ex` | Month grid, grouping, load helpers |
| Create | `lib/tugas_web/components/duty_calendar.ex` | Calendar grid, someday strip, day modal |
| Create | `lib/tugas_web/components/dashboard_todos_panel.ex` | Sidebar todos preview |
| Modify | `lib/tugas_web/live/dashboard_live/index.ex` | LiveView mount, events, render |
| Modify | `lib/tugas_web/components/layouts.ex` | `container_class` attr + Dashboard nav link |
| Create | `test/tugas_web/live/dashboard_live/calendar_helpers_test.exs` | Unit tests for grid/grouping |
| Modify | `test/tugas/duties_test.exs` | Date-bound `list_duties` tests |
| Modify | `test/tugas_web/live/dashboard_live_test.exs` | LiveView integration tests |

---

### Task 1: Date-bound `list_duties/2`

**Files:**
- Modify: `lib/tugas/duties.ex` (inside `list_duties/2` query pipeline, after `apply_status_filter`)
- Test: `test/tugas/duties_test.exs`

**Interfaces:**
- Produces: `Duties.list_duties(scope, status:, due_before:, due_after:, dateless:)` where:
  - `:due_before` — `%Date{}` → `WHERE due_by <= ^d`
  - `:due_after` — `%Date{}` → `WHERE due_by > ^d` (exclusive; pass `Date.add(start, -1)` for `>= start`)
  - `:dateless` — `true` → `WHERE due_by IS NULL` (mutually exclusive with date bounds in practice)
  - All opts optional; omitted opts are no-ops (reuse existing `apply_due_bound/3` from `list_duties_page`)

- [ ] **Step 1: Write the failing tests**

Add to `test/tugas/duties_test.exs` inside an existing `describe` or a new `describe "list_duties/2 date filters"`:

```elixir
  describe "list_duties/2 date filters" do
    setup do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = Tugas.DutiesFixtures.type_fixture(manager.entity)

      {:ok, early} =
        Tugas.Duties.create_duty(manager, %{
          title: "Early",
          duty_type_id: type.id,
          due_by: ~D[2026-06-05],
          open_note: "early"
        })

      {:ok, mid} =
        Tugas.Duties.create_duty(manager, %{
          title: "Mid",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "mid"
        })

      {:ok, late} =
        Tugas.Duties.create_duty(manager, %{
          title: "Late",
          duty_type_id: type.id,
          due_by: ~D[2026-06-25],
          open_note: "late"
        })

      {:ok, someday} =
        Tugas.Duties.create_duty(manager, %{
          title: "Someday duty",
          duty_type_id: type.id,
          someday: true,
          open_note: "someday"
        })

      %{manager: manager, early: early, mid: mid, late: late, someday: someday}
    end

    test "due_after and due_before restrict to a month window", %{
      manager: manager,
      early: early,
      mid: mid,
      late: late
    } do
      duties =
        Tugas.Duties.list_duties(manager,
          status: :live,
          due_after: ~D[2026-06-01],
          due_before: ~D[2026-06-20]
        )

      ids = Enum.map(duties, & &1.id)
      assert early.id in ids
      assert mid.id in ids
      refute late.id in ids
    end

    test "dateless: true returns only nil due_by duties", %{
      manager: manager,
      someday: someday,
      mid: mid
    } do
      duties = Tugas.Duties.list_duties(manager, status: :live, dateless: true)
      ids = Enum.map(duties, & &1.id)
      assert someday.id in ids
      refute mid.id in ids
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/duties_test.exs --only line:LINE_OF_FIRST_NEW_TEST`
(Or grep the line number after adding.)

Expected: FAIL — unknown opts ignored; `dateless` duties mixed in or wrong counts.

- [ ] **Step 3: Implement date filters on `list_duties/2`**

In `lib/tugas/duties.ex`, change the `list_duties` query pipeline from:

```elixir
    Duty
    |> where([o], o.entity_id == ^entity.id)
    |> scope_to_assignee(status, user)
    |> apply_status_filter(status)
    |> apply_list_order(status)
```

to:

```elixir
    Duty
    |> where([o], o.entity_id == ^entity.id)
    |> scope_to_assignee(status, user)
    |> apply_status_filter(status)
    |> apply_due_bound(:before, Keyword.get(opts, :due_before))
    |> apply_due_bound(:after, Keyword.get(opts, :due_after))
    |> apply_dateless_filter(Keyword.get(opts, :dateless))
    |> apply_list_order(status)
```

Add near `apply_due_bound/3`:

```elixir
  defp apply_dateless_filter(query, true), do: where(query, [o], is_nil(o.due_by))
  defp apply_dateless_filter(query, _), do: query
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas/duties_test.exs -k "date filters"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tugas/duties.ex test/tugas/duties_test.exs
git commit -m "feat: add date-bound and dateless filters to list_duties/2"
```

---

### Task 2: `DashboardLive.CalendarHelpers`

**Files:**
- Create: `lib/tugas_web/live/dashboard_live/calendar_helpers.ex`
- Create: `test/tugas_web/live/dashboard_live/calendar_helpers_test.exs`

**Interfaces:**
- Produces:
  - `build_month_grid(year, month, today) :: %{year: integer, month: integer, weeks: [[cell]]}` where `cell = %{date: Date.t(), in_month?: boolean, today?: boolean}`
  - `month_range(year, month) :: {Date.t(), Date.t()}`
  - `group_by_date(rows) :: %{Date.t() => [row]}` (rows are maps from `IndexHelpers.build_rows/2`)
  - `load_month_rows(scope, today, mine?, year, month) :: [row]`
  - `load_someday_rows(scope, today, mine?) :: [row]`

- [ ] **Step 1: Write the failing tests**

Create `test/tugas_web/live/dashboard_live/calendar_helpers_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/dashboard_live/calendar_helpers_test.exs`
Expected: FAIL — module not found

- [ ] **Step 3: Implement `CalendarHelpers`**

Create `lib/tugas_web/live/dashboard_live/calendar_helpers.ex`:

```elixir
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
    # Sunday-start week (wday 7 = Sunday in Elixir)
    days_back = if date.day_of_week == 7, do: 0, else: date.day_of_week
    Date.add(date, -days_back)
  end

  defp end_of_week(date) do
    days_forward = if date.day_of_week == 7, do: 6, else: 6 - date.day_of_week
    Date.add(date, days_forward)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/live/dashboard_live/calendar_helpers_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/dashboard_live/calendar_helpers.ex \
        test/tugas_web/live/dashboard_live/calendar_helpers_test.exs
git commit -m "feat: add DashboardLive.CalendarHelpers for month grid"
```

---

### Task 3: Layout shell — wider container + Dashboard nav link

**Files:**
- Modify: `lib/tugas_web/components/layouts.ex`
- Test: `test/tugas_web/live/dashboard_live_test.exs` (nav assertion added in Task 6; quick manual check here)

**Interfaces:**
- Produces: `Layouts.app/1` accepts `container_class` attr (default `"max-w-4xl"`).
- Produces: `entity_nav/1` renders **📅 Dashboard** as the first link to `/entities/:slug`.

- [ ] **Step 1: Add `container_class` attr**

In `lib/tugas_web/components/layouts.ex`, after the `current_scope` attr on `app/1`:

```elixir
  attr :container_class, :string, default: "max-w-4xl"
```

Change the main wrapper from:

```heex
        <div class="mx-auto max-w-4xl space-y-3">
```

to:

```heex
        <div class={["mx-auto space-y-3", @container_class]}>
```

- [ ] **Step 2: Add Dashboard nav link**

In `entity_nav/1`, before the Duties link:

```heex
        <.entity_nav_link
          href={~p"/entities/#{@current_scope.entity.slug}"}
          label="📅 Dashboard"
        />
```

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 4: Commit**

```bash
git add lib/tugas_web/components/layouts.ex
git commit -m "feat: add Dashboard nav link and configurable layout width"
```

---

### Task 4: `DutyCalendar` component

**Files:**
- Create: `lib/tugas_web/components/duty_calendar.ex`

**Interfaces:**
- Consumes: `grid` from `CalendarHelpers.build_month_grid/3`, `grouped` from `group_by_date/1`, `someday_rows`, `slug`, `today`, optional `day_modal_date` + `day_modal_rows`
- Produces: function components `duty_calendar/1`, `duty_chip/1`, `day_modal/1`

- [ ] **Step 1: Create the component module**

Create `lib/tugas_web/components/duty_calendar.ex`:

```elixir
defmodule TugasWeb.DutyCalendar do
  @moduledoc false
  use TugasWeb, :html

  import TugasWeb.UrgencyBadge, only: [tier_border: 1]

  alias TugasWeb.DashboardLive.CalendarHelpers

  attr :grid, :map, required: true
  attr :grouped, :map, required: true
  attr :someday_rows, :list, required: true
  attr :slug, :string, required: true
  attr :day_modal_date, :any, default: nil
  attr :day_modal_rows, :list, default: []

  def duty_calendar(assigns) do
    ~H"""
    <div id="duty-calendar" class="space-y-4">
      <div class="grid grid-cols-7 gap-px bg-base-300 rounded-lg overflow-hidden border border-base-300">
        <div
          :for={label <- ~w(Sun Mon Tue Wed Thu Fri Sat)}
          class="bg-base-200 px-2 py-1.5 text-center text-xs font-semibold text-base-content/70"
        >
          {label}
        </div>
        <div
          :for={cell <- @grid.weeks |> List.flatten()}
          id={"calendar-day-#{cell.date}"}
          class={[
            "bg-base-100 min-h-24 p-1 space-y-0.5",
            !cell.in_month? && "bg-base-200/40 text-base-content/40",
            cell.today? && "ring-2 ring-inset ring-primary/40"
          ]}
        >
          <div class="text-xs font-medium px-0.5">{cell.date.day}</div>
          <%= for {row, idx} <- Enum.with_index(Map.get(@grouped, cell.date, [])) do %>
            <.duty_chip
              :if={idx < CalendarHelpers.max_chips_per_day()}
              row={row}
              slug={@slug}
            />
          <% end %>
          <%= if length(Map.get(@grouped, cell.date, [])) > CalendarHelpers.max_chips_per_day() do %>
            <% extra = length(Map.get(@grouped, cell.date, [])) - CalendarHelpers.max_chips_per_day() %>
            <button
              type="button"
              id={"calendar-day-more-#{cell.date}"}
              phx-click="open_day_modal"
              phx-value-date={Date.to_iso8601(cell.date)}
              class="text-xs text-primary hover:underline px-0.5"
            >
              +{extra} more
            </button>
          <% end %>
        </div>
      </div>

      <section :if={@someday_rows != []} id="someday-strip" class="space-y-2">
        <h3 class="text-sm font-semibold text-base-content/70">Someday</h3>
        <div class="flex flex-wrap gap-1">
          <.duty_chip :for={row <- @someday_rows} row={row} slug={@slug} />
        </div>
      </section>

      <.day_modal
        :if={@day_modal_date}
        date={@day_modal_date}
        rows={@day_modal_rows}
        slug={@slug}
      />
    </div>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true

  defp duty_chip(assigns) do
    ~H"""
    <.link
      id={"duty-chip-#{@row.duty.id}"}
      navigate={~p"/entities/#{@slug}/duties/#{@row.duty.id}"}
      class={[
        "block text-xs px-1.5 py-0.5 rounded border-l-2 truncate hover:bg-base-200",
        tier_border(@row.tier)
      ]}
    >
      <span class="font-medium">{@row.duty.title}</span>
      <span class="text-base-content/50 ml-1">{@row.duty.duty_type.name}</span>
    </.link>
    """
  end

  attr :date, :any, required: true
  attr :rows, :list, required: true
  attr :slug, :string, required: true

  defp day_modal(assigns) do
    ~H"""
    <div id="day-modal" class="modal modal-open">
      <div class="modal-box max-w-md">
        <h3 class="font-bold text-lg">
          {Calendar.strftime(@date, "%A, %B %-d")}
        </h3>
        <ul class="mt-3 space-y-1">
          <li :for={row <- @rows}>
            <.duty_chip row={row} slug={@slug} />
          </li>
        </ul>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_day_modal">Close</button>
        </div>
      </div>
      <button class="modal-backdrop" type="button" phx-click="close_day_modal" aria-label="Close" />
    </div>
    """
  end
end
```

Register in `lib/tugas_web.ex` `html_helpers` if components aren't auto-imported — check if other components like `UrgencyBadge` are imported globally. If `duty_calendar` is not auto-available, add to imports in `html_helpers` block:

```elixir
import TugasWeb.DutyCalendar, only: [duty_calendar: 1]
```

Or use fully qualified `<TugasWeb.DutyCalendar.duty_calendar …>` in the LiveView.

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: PASS (fix `day_of_week` if needed — Elixir 1.19 uses `Date.day_of_week/2`; default calendar is `:monday` — **use `:sunday` for Sun-start grid**)

**Fix `start_of_week/1` and `end_of_week/1` to use Sunday start:**

```elixir
  defp start_of_week(date) do
    dow = Date.day_of_week(date, :sunday)
    Date.add(date, -dow)
  end

  defp end_of_week(date) do
    dow = Date.day_of_week(date, :sunday)
    Date.add(date, 6 - dow)
  end
```

Update Task 2 implementation accordingly.

- [ ] **Step 3: Commit**

```bash
git add lib/tugas_web/components/duty_calendar.ex lib/tugas_web.ex
git commit -m "feat: add DutyCalendar component for dashboard month grid"
```

---

### Task 5: `DashboardTodosPanel` component

**Files:**
- Create: `lib/tugas_web/components/dashboard_todos_panel.ex`

**Interfaces:**
- Consumes: `todos` list (plain `%Todo{}` structs), `slug`
- Produces: `dashboard_todos_panel/1` with checkbox `phx-click="toggle_todo_complete"`

- [ ] **Step 1: Create the component**

Create `lib/tugas_web/components/dashboard_todos_panel.ex`:

```elixir
defmodule TugasWeb.DashboardTodosPanel do
  @moduledoc false
  use TugasWeb, :html

  alias Tugas.Todos.Todo

  attr :todos, :list, required: true
  attr :slug, :string, required: true

  def dashboard_todos_panel(assigns) do
    ~H"""
    <aside id="dashboard-todos" class="space-y-3 lg:sticky lg:top-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Todos</h2>
        <.link navigate={~p"/entities/#{@slug}/todos"} class="text-sm link link-primary">
          View all →
        </.link>
      </div>

      <ul :if={@todos != []} id="dashboard-todos-list" class="space-y-2">
        <li :for={todo <- @todos} id={"dashboard-todo-#{todo.id}"} class="flex items-start gap-2">
          <input
            type="checkbox"
            class="checkbox checkbox-sm mt-0.5"
            checked={Todo.completed?(todo)}
            phx-click="toggle_todo_complete"
            phx-value-id={todo.id}
          />
          <span class="text-sm truncate">{todo.title}</span>
        </li>
      </ul>

      <p :if={@todos == []} class="text-sm text-base-content/60">
        No open todos.
        <.link navigate={~p"/entities/#{@slug}/todos"} class="link link-primary">Add one</.link>
      </p>
    </aside>
    """
  end
end
```

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add lib/tugas_web/components/dashboard_todos_panel.ex
git commit -m "feat: add DashboardTodosPanel sidebar component"
```

---

### Task 6: `DashboardLive.Index` LiveView

**Files:**
- Modify: `lib/tugas_web/live/dashboard_live/index.ex`
- Modify: `test/tugas_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: all modules from Tasks 1–5
- Produces: working dashboard at `/entities/:slug`

- [ ] **Step 1: Replace placeholder tests**

Replace `test/tugas_web/live/dashboard_live_test.exs` with:

```elixir
defmodule TugasWeb.DashboardLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  alias Tugas.Duties
  alias Tugas.Duties.Urgency
  alias Tugas.Todos

  setup :register_and_log_in_user

  test "renders calendar with nav links", %{conn: conn} do
    scope = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}")

    refute html =~ "Dashboard coming soon"
    assert has_element?(view, "#duty-calendar")
    assert has_element?(view, "#dashboard-todos")
    assert html =~ "📅 Dashboard"
    assert html =~ "💼 Duties"
  end

  test "duty appears on its due date cell", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-18]

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Tax filing",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#calendar-day-#{due} #duty-chip-#{duty.id}", "Tax filing")
  end

  test "overdue duty chip has error border class", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, reminder_offsets: "7,1")
    today = Urgency.today_for(manager.entity.timezone)
    due = Date.add(today, -3)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Overdue task",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#duty-chip-#{duty.id}.border-error")
  end

  test "someday duty appears in someday strip not calendar day", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "No date task",
        duty_type_id: type.id,
        someday: true,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#someday-strip #duty-chip-#{duty.id}")
  end

  test "mine scope hides other members' unassigned duties", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    member = member_scope_on_entity(manager.entity)
    conn = log_in_user(conn, member.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Team only duty",
        duty_type_id: type.id,
        due_by: ~D[2026-06-20],
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{member.entity.slug}")

    refute has_element?(view, "#duty-chip-#{duty.id}")

    view |> element("#dashboard-scope-mine") |> render_click()
    refute has_element?(view, "#duty-chip-#{duty.id}")

    view |> element("#dashboard-scope-team") |> render_click()
    assert has_element?(view, "#duty-chip-#{duty.id}")
  end

  test "prev month navigation updates duties shown", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    today = Urgency.today_for(manager.entity.timezone)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Last month duty",
        duty_type_id: type.id,
        due_by: Date.add(today, -40),
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")
    refute has_element?(view, "#duty-chip-#{duty.id}")

    view |> element("#dashboard-prev-month") |> render_click()
    assert has_element?(view, "#duty-chip-#{duty.id}")
  end

  test "open todo appears in sidebar and can be completed", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, todo} = Todos.create_todo(manager, %{title: "Buy milk"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#dashboard-todo-#{todo.id}", "Buy milk")

    view |> element("#dashboard-todo-#{todo.id} input[type=checkbox]") |> render_click()

    refute has_element?(view, "#dashboard-todo-#{todo.id}")
  end

  test "day overflow opens modal with all duties", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-22]

    for title <- ["One", "Two", "Three", "Four"] do
      {:ok, _duty} =
        Duties.create_duty(manager, %{
          title: title,
          duty_type_id: type.id,
          due_by: due,
          open_note: "open"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "#calendar-day-more-#{due}", "+1 more")

    view |> element("#calendar-day-more-#{due}") |> render_click()
    assert has_element?(view, "#day-modal")
    assert render(view) =~ "Four"
  end
end
```

Add `import Tugas.DutiesFixtures` helpers — use `member_scope_on_entity/1` from fixtures.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs`
Expected: FAIL — placeholder or missing elements

- [ ] **Step 3: Implement `DashboardLive.Index`**

Replace `lib/tugas_web/live/dashboard_live/index.ex`:

```elixir
defmodule TugasWeb.DashboardLive.Index do
  use TugasWeb, :live_view

  alias Tugas.Duties.Urgency
  alias Tugas.Todos
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DutiesFilter
  alias TugasWeb.DutyLive.IndexHelpers, as: Index

  @todo_preview_limit 15

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} container_class="max-w-7xl">
      <div id="dashboard" class="tugas-page space-y-4">
        <.header>Dashboard</.header>

        <div class="flex flex-col lg:flex-row gap-6">
          <div class="flex-1 min-w-0 space-y-3">
            <div class="flex flex-wrap items-center gap-2">
              <div id="dashboard-scope-toggle" class="tabs tabs-box">
                <button
                  id="dashboard-scope-mine"
                  type="button"
                  phx-click="set_scope"
                  phx-value-mine="true"
                  class={["tab", @mine? && "tab-active font-bold"]}
                >
                  Mine
                </button>
                <button
                  id="dashboard-scope-team"
                  type="button"
                  phx-click="set_scope"
                  phx-value-mine="false"
                  class={["tab", !@mine? && "tab-active font-bold"]}
                >
                  Team
                </button>
              </div>

              <div class="flex items-center gap-1 ml-auto">
                <button id="dashboard-prev-month" type="button" class="btn btn-ghost btn-sm" phx-click="prev_month">
                  ‹
                </button>
                <span id="dashboard-month-label" class="text-sm font-semibold min-w-32 text-center">
                  {Calendar.month_label(@year, @month)}
                </span>
                <button id="dashboard-next-month" type="button" class="btn btn-ghost btn-sm" phx-click="next_month">
                  ›
                </button>
                <button id="dashboard-today" type="button" class="btn btn-ghost btn-sm" phx-click="today">
                  Today
                </button>
              </div>
            </div>

            <TugasWeb.DutyCalendar.duty_calendar
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
            />
          </div>

          <div class="w-full lg:w-80 shrink-0">
            <TugasWeb.DashboardTodosPanel.dashboard_todos_panel
              todos={@todos}
              slug={@current_scope.entity.slug}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    {year, month} = Calendar.current_month(today)

    socket =
      socket
      |> assign(:today, today)
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:day_modal_date, nil)
      |> assign(:day_modal_rows, [])
      |> DutiesFilter.assign_filters(session)
      |> load_dashboard()

    {:ok, socket}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket
     |> assign(:mine?, mine == "true")
     |> load_dashboard()
     |> DutiesFilter.persist()}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, -1)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, 1)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("today", _params, socket) do
    today = socket.assigns.today
    {year, month} = Calendar.current_month(today)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("open_day_modal", %{"date" => iso}, socket) do
    date = Date.from_iso8601!(iso)
    rows = Map.get(socket.assigns.grouped, date, [])

    {:noreply,
     assign(socket, day_modal_date: date, day_modal_rows: rows)}
  end

  def handle_event("close_day_modal", _params, socket) do
    {:noreply, assign(socket, day_modal_date: nil, day_modal_rows: [])}
  end

  def handle_event("toggle_todo_complete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    result =
      with {:ok, todo} <- Todos.get_todo(scope, id),
           :ok <- complete_or_reopen(scope, todo) do
        :ok
      else
        _ -> :error
      end

    socket =
      case result do
        :ok -> load_todos(socket)
        :error -> socket
      end

    {:noreply, socket}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    if socket.assigns.day_modal_date do
      {:noreply, assign(socket, day_modal_date: nil, day_modal_rows: [])}
    else
      {:noreply, socket}
    end
  end

  defp load_dashboard(socket) do
    %{current_scope: scope, today: today, mine?: mine?, year: year, month: month} =
      socket.assigns

    month_rows = Calendar.load_month_rows(scope, today, mine?, year, month)
    someday_rows = Calendar.load_someday_rows(scope, today, mine?)
    grid = Calendar.build_month_grid(year, month, today)
    grouped = Calendar.group_by_date(month_rows)

    socket
    |> assign(grid: grid, grouped: grouped, someday_rows: someday_rows)
    |> load_todos()
  end

  defp load_todos(socket) do
    scope = socket.assigns.current_scope

    todos =
      case Todos.list_todos_page(scope, status: :open, limit: @todo_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    assign(socket, :todos, todos)
  end

  defp complete_or_reopen(scope, todo) do
    case Todos.toggle_complete(scope, todo) do
      {:ok, _} -> :ok
      :not_authorise -> :error
      :not_found -> :error
    end
  end
end
```

**Note:** `DutiesFilter.assign_filters/2` assigns `lifecycle`, `query`, `sort` too — dashboard ignores them but they must exist if `persist/1` is called (it reads `socket.assigns.lifecycle` etc.). `assign_filters` already sets all four — no change needed.

- [ ] **Step 4: Run dashboard tests**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs`
Expected: PASS (fix selectors/date fixtures as needed)

- [ ] **Step 5: Run duty list regression**

Run: `mix test test/tugas_web/live/duty_live/index_test.exs`
Expected: PASS — duties page unchanged

- [ ] **Step 6: Commit**

```bash
git add lib/tugas_web/live/dashboard_live/index.ex test/tugas_web/live/dashboard_live_test.exs
git commit -m "feat: implement desktop dashboard calendar with todos sidebar"
```

---

### Task 7: Final verification

**Files:** (none — verification only)

- [ ] **Step 1: Run full precommit**

Run: `mix precommit`
Expected: compile (no warnings), format clean, all tests pass

- [ ] **Step 2: Commit any format fixes**

```bash
git add -A
git commit -m "chore: format dashboard calendar feature"
```

(Only if precommit produced changes.)

---

## Self-Review

| Spec requirement | Task |
|------------------|------|
| Live duties only on calendar | Task 1 + Task 2 `load_month_rows` |
| Month grid Sun–Sat | Task 2 + Task 4 |
| Someday strip | Task 2 `load_someday_rows` + Task 4 |
| Urgency tier colors | Task 4 `tier_border` |
| Mine/Team toggle | Task 6 |
| Todos sidebar (15 open, complete, view all) | Task 5 + Task 6 |
| Dashboard nav link | Task 3 |
| Duties page unchanged | No task touches `DutyLive.Index` |
| Wider layout | Task 3 `container_class` |
| Day overflow modal | Task 4 + Task 6 |
| `close_modal_on_escape` | Task 6 |
| Mobile unchanged | No mobile files in plan |

No placeholders remain. `Date.day_of_week/2` with `:sunday` is called out explicitly in Task 4.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-27-dashboard-calendar.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — implement tasks in this session with checkpoints

Which approach?