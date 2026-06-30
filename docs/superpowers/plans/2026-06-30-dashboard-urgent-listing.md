# Dashboard "Most Urgent" Listing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Most Urgent" duties listing (overdue → due-soon, ranked) to the left of the calendar on both the desktop and mobile dashboards, keeping the existing Someday section unchanged.

**Architecture:** A new `CalendarHelpers.load_urgent_rows/3` reuses the existing `Index.build_calendar_rows/2` + `Urgency.classify` to load and rank live duties flagged for attention. `DashboardLive.IndexHelpers` assigns `:urgent_rows` (shared by both dashboards). A new `urgent_panel/1` component renders the listing — desktop as a capped left column with a "+N more" modal; mobile as a full-screen scrollable swipe panel inserted directly left of the calendar.

**Tech Stack:** Elixir/Phoenix 1.8 LiveView, Tailwind v4 + daisyUI 5, ExUnit (`Tugas.DataCase`, `Phoenix.LiveViewTest`).

## Global Constraints

- Reuse `Tugas.Duties.Urgency` as-is — no new urgency math.
- Urgency `today` is **always** `Urgency.today_for(scope.entity.timezone)`, never `Date.utc_today()`.
- Unauthorized context calls return `:not_authorise` → treat as `[]`.
- Every LiveView in the shell must keep a working `close_modal_on_escape` clause.
- Duty chips reuse the shared `duty_chip` component (countdown badge + tier border consistency).
- Run `mix precommit` before declaring work done (compile --warnings-as-errors, format, test).
- Spec: `docs/superpowers/specs/2026-06-30-dashboard-urgent-listing-design.md`.

---

### Task 1: `load_urgent_rows/3` data helper

**Files:**
- Modify: `lib/tugas_web/live/dashboard_live/calendar_helpers.ex`
- Test: `test/tugas_web/live/dashboard_live/calendar_helpers_test.exs`

**Interfaces:**
- Consumes: `Tugas.Duties.list_calendar_duties/2`, `TugasWeb.DutyLive.IndexHelpers.build_calendar_rows/2` (aliased `Index`), `Index.status_atom/2`.
- Produces:
  - `CalendarHelpers.load_urgent_rows(scope, today, mine?) :: [%{duty: Duty.t(), cycle_status: :live, urgency: atom, tier: atom}]` — live duties with `urgency in [:overdue, :due_soon]`, ranked `overdue` then `due_soon`, then `due_by` ascending.
  - `CalendarHelpers.max_urgent_chips() :: 10`

- [ ] **Step 1: Write the failing test**

Add to `test/tugas_web/live/dashboard_live/calendar_helpers_test.exs` (note `use Tugas.DataCase` is already at the top):

```elixir
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/dashboard_live/calendar_helpers_test.exs -v`
Expected: FAIL — `function CalendarHelpers.load_urgent_rows/3 is undefined`.

- [ ] **Step 3: Write minimal implementation**

In `lib/tugas_web/live/dashboard_live/calendar_helpers.ex`, add the module attribute near the existing `@max_someday_chips` (top of module):

```elixir
  @urgent_window_days 365
  @max_urgent_chips 10
```

Add accessor near `max_someday_chips/0`:

```elixir
  def max_urgent_chips, do: @max_urgent_chips
```

Add the loader near `load_someday_rows/3`:

```elixir
  def load_urgent_rows(%Scope{} = scope, today, mine?) do
    status = Index.status_atom(mine?, :live)
    horizon = Date.add(today, @urgent_window_days)

    duties =
      case Duties.list_calendar_duties(scope, status: status, due_before: horizon) do
        :not_authorise -> []
        list -> list
      end

    Index.build_calendar_rows(duties, today)
    |> Enum.filter(fn %{urgency: u} -> u in [:overdue, :due_soon] end)
    |> Enum.sort_by(fn %{duty: d, urgency: u} -> {urgent_rank(u), d.due_by} end)
  end

  defp urgent_rank(:overdue), do: 0
  defp urgent_rank(:due_soon), do: 1
```

(`due_before` excludes null `due_by`, so dateless duties never enter; overdue rows are below the horizon and are included.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/live/dashboard_live/calendar_helpers_test.exs -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/dashboard_live/calendar_helpers.ex test/tugas_web/live/dashboard_live/calendar_helpers_test.exs
git commit -m "feat(dashboard): add load_urgent_rows/3 for the urgent listing"
```

---

### Task 2: Wiring, components, and desktop dashboard render

**Files:**
- Modify: `lib/tugas_web/live/dashboard_live/index_helpers.ex`
- Modify: `lib/tugas_web/components/duty_calendar.ex`
- Modify: `lib/tugas_web/live/dashboard_live/index.ex`
- Test: `test/tugas_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `CalendarHelpers.load_urgent_rows/3`, `CalendarHelpers.max_urgent_chips/0` (Task 1); existing `duty_chip/1` private component.
- Produces:
  - `IndexHelpers` assigns `:urgent_rows`, `:urgent_modal_open?`; functions `handle_open_urgent_modal/1`, `handle_close_urgent_modal/1`.
  - `TugasWeb.DutyCalendar.urgent_panel/1` — public component, attrs `rows` (list, required), `slug` (string, required), `variant` (atom, default `:desktop`), `modal_open?` (boolean, default `false`).
  - LiveView events `"open_urgent_modal"` / `"close_urgent_modal"`.

- [ ] **Step 1: Write the failing tests**

Add to `test/tugas_web/live/dashboard_live_test.exs`:

```elixir
test "urgent duty appears in urgent panel; non-urgent and someday excluded", %{conn: conn} do
  manager = Tugas.EntitiesFixtures.manager_scope_fixture()
  conn = log_in_user(conn, manager.user)
  type = type_fixture(manager.entity, reminder_offsets: "7")
  today = Urgency.today_for(manager.entity.timezone)

  {:ok, urgent} =
    Duties.create_duty(manager, %{
      title: "Overdue task",
      duty_type_id: type.id,
      due_by: Date.add(today, -2),
      open_note: "open"
    })

  {:ok, calm} =
    Duties.create_duty(manager, %{
      title: "Far off",
      duty_type_id: type.id,
      due_by: Date.add(today, 60),
      open_note: "open"
    })

  {:ok, someday} =
    Duties.create_duty(manager, %{
      title: "No date",
      duty_type_id: type.id,
      someday: true,
      open_note: "open"
    })

  {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

  assert has_element?(view, "#urgent-panel #urgent-duty-chip-#{urgent.id}")
  refute has_element?(view, "#urgent-panel #urgent-duty-chip-#{calm.id}")
  refute has_element?(view, "#urgent-panel #urgent-duty-chip-#{someday.id}")
end

test "urgent overflow shows +N more, opens and closes modal", %{conn: conn} do
  manager = Tugas.EntitiesFixtures.manager_scope_fixture()
  conn = log_in_user(conn, manager.user)
  type = type_fixture(manager.entity, reminder_offsets: "30")
  today = Urgency.today_for(manager.entity.timezone)

  for n <- 1..10 do
    {:ok, _} =
      Duties.create_duty(manager, %{
        title: "Urgent #{String.pad_leading("#{n}", 2, "0")}",
        duty_type_id: type.id,
        due_by: Date.add(today, n),
        open_note: "open"
      })
  end

  {:ok, hidden} =
    Duties.create_duty(manager, %{
      title: "Urgent hidden",
      duty_type_id: type.id,
      due_by: Date.add(today, 20),
      open_note: "open"
    })

  {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

  assert has_element?(view, "#urgent-more", "+1 more")
  refute has_element?(view, "#urgent-panel #urgent-duty-chip-#{hidden.id}")

  view |> element("#urgent-more") |> render_click()
  assert has_element?(view, "#urgent-modal #urgent-modal-duty-chip-#{hidden.id}")

  view |> element("#urgent-modal button", "Close") |> render_click()
  refute has_element?(view, "#urgent-modal")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs -v`
Expected: FAIL — no `#urgent-panel` element rendered.

- [ ] **Step 3: Wire IndexHelpers**

In `lib/tugas_web/live/dashboard_live/index_helpers.ex`:

In `mount_dashboard/2`, add the assign next to `:someday_modal_open?`:

```elixir
      |> assign(:someday_modal_open?, false)
      |> assign(:urgent_modal_open?, false)
```

In `load_dashboard/1`, add the load + assign next to `someday_rows`:

```elixir
    month_rows = Calendar.load_month_rows(scope, today, mine?, year, month)
    someday_rows = Calendar.load_someday_rows(scope, today, mine?)
    urgent_rows = Calendar.load_urgent_rows(scope, today, mine?)
    holidays_by_date = Calendar.load_holidays_by_date(scope, year, month)
```

and in the `assign(...)` block of `load_dashboard/1`:

```elixir
    |> assign(
      grid: grid,
      grouped: grouped,
      someday_rows: someday_rows,
      urgent_rows: urgent_rows,
      holidays_by_date: holidays_by_date
    )
```

Add the handlers next to `handle_close_someday_modal/1`:

```elixir
  def handle_open_urgent_modal(socket) do
    socket
    |> assign(:urgent_modal_open?, true)
    |> assign(day_modal_date: nil, day_modal_rows: [])
  end

  def handle_close_urgent_modal(socket) do
    assign(socket, :urgent_modal_open?, false)
  end
```

Extend `handle_close_modal_on_escape/1` to also close the urgent modal:

```elixir
  def handle_close_modal_on_escape(socket) do
    cond do
      socket.assigns.day_modal_date ->
        handle_close_day_modal(socket)

      socket.assigns.someday_modal_open? ->
        handle_close_someday_modal(socket)

      socket.assigns.urgent_modal_open? ->
        handle_close_urgent_modal(socket)

      true ->
        socket
    end
  end
```

- [ ] **Step 4: Add the `urgent_panel/1` + `urgent_modal/1` components**

In `lib/tugas_web/components/duty_calendar.ex`, add after `mobile_someday_panel/1` (around line 126):

```elixir
  attr :rows, :list, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop
  attr :modal_open?, :boolean, default: false

  def urgent_panel(assigns) do
    assigns =
      assigns
      |> assign(:mobile?, assigns.variant == :mobile)
      |> assign(:max_urgent, CalendarHelpers.max_urgent_chips())

    ~H"""
    <section id={urgent_panel_id(@mobile?)} class={urgent_panel_class(@mobile?)}>
      <h2 :if={@mobile?} class="shrink-0 text-lg font-semibold text-base-content/80 pb-2">
        Urgent
      </h2>
      <h3 :if={!@mobile?} class="shrink-0 text-sm font-semibold text-base-content/70 pb-2">
        Urgent
      </h3>

      <p :if={@rows == []} class="text-sm text-base-content/60">
        Nothing overdue or due soon.
      </p>

      <ul :if={@rows != [] and @mobile?} class="min-h-0 flex-1 space-y-2 overflow-y-auto">
        <li :for={row <- @rows}>
          <.duty_chip
            row={row}
            slug={@slug}
            variant={@variant}
            id_prefix="urgent-panel-duty-chip"
            layout={:list}
          />
        </li>
      </ul>

      <ul :if={@rows != [] and !@mobile?} class="min-h-0 flex-1 space-y-2 overflow-y-auto">
        <%= for {row, idx} <- Enum.with_index(@rows) do %>
          <li :if={idx < @max_urgent}>
            <.duty_chip
              row={row}
              slug={@slug}
              variant={@variant}
              id_prefix="urgent-duty-chip"
              layout={:list}
            />
          </li>
        <% end %>
      </ul>

      <%= if !@mobile? and length(@rows) > @max_urgent do %>
        <% extra = length(@rows) - @max_urgent %>
        <button
          type="button"
          id="urgent-more"
          phx-click="open_urgent_modal"
          class="shrink-0 text-xs text-primary hover:underline px-0.5 pt-1"
        >
          +{extra} more
        </button>
      <% end %>

      <.urgent_modal :if={!@mobile? and @modal_open?} rows={@rows} slug={@slug} variant={@variant} />
    </section>
    """
  end

  defp urgent_panel_id(true), do: "m-dashboard-urgent"
  defp urgent_panel_id(false), do: "urgent-panel"

  defp urgent_panel_class(true), do: "h-full min-h-0 flex flex-col px-1"

  defp urgent_panel_class(false),
    do: "flex h-full min-h-0 min-w-0 flex-col rounded-lg border border-base-300 bg-base-200/40 p-3"

  attr :rows, :list, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop

  defp urgent_modal(assigns) do
    ~H"""
    <div id="urgent-modal" class="modal modal-open">
      <div class="modal-box max-w-md">
        <h3 class="font-bold text-lg">Urgent</h3>
        <ul class="mt-3 space-y-2 max-h-[70vh] overflow-y-auto">
          <li :for={row <- @rows}>
            <.duty_chip
              row={row}
              slug={@slug}
              variant={@variant}
              id_prefix="urgent-modal-duty-chip"
              layout={:list}
            />
          </li>
        </ul>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_urgent_modal">Close</button>
        </div>
      </div>
      <button
        class="modal-backdrop"
        type="button"
        phx-click="close_urgent_modal"
        aria-label="Close"
      />
    </div>
    """
  end
```

(`CalendarHelpers` is already aliased in this module; `duty_chip/1` is defined later in the same module.)

- [ ] **Step 5: Render the panel on the desktop dashboard**

In `lib/tugas_web/live/dashboard_live/index.ex`, change the grid wrapper (line 65) and add the panel as the first column:

```elixir
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-[15%_minmax(0,1fr)_15%]">
          <.urgent_panel
            rows={@urgent_rows}
            slug={@current_scope.entity.slug}
            modal_open?={@urgent_modal_open?}
          />

          <div class="flex h-full min-h-0 min-w-0 flex-col">
            <.duty_calendar
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
              day_modal_holidays={@day_modal_holidays}
              someday_modal_open?={@someday_modal_open?}
            />
          </div>

          <.dashboard_todos_panel
            todos={@todos}
            completed_todos={@completed_todos}
            slug={@current_scope.entity.slug}
            row_effects={@row_effects}
          />
        </div>
```

Add the event handlers next to the existing `close_someday_modal` clause (after line 125):

```elixir
  def handle_event("open_urgent_modal", _params, socket) do
    {:noreply, Dashboard.handle_open_urgent_modal(socket)}
  end

  def handle_event("close_urgent_modal", _params, socket) do
    {:noreply, Dashboard.handle_close_urgent_modal(socket)}
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs -v`
Expected: PASS (new tests pass; existing Someday/calendar tests still pass).

- [ ] **Step 7: Commit**

```bash
git add lib/tugas_web/live/dashboard_live/index_helpers.ex lib/tugas_web/components/duty_calendar.ex lib/tugas_web/live/dashboard_live/index.ex test/tugas_web/live/dashboard_live_test.exs
git commit -m "feat(dashboard): add Most Urgent listing left of the desktop calendar"
```

---

### Task 3: Mobile dashboard panel + swipe hook

**Files:**
- Modify: `lib/tugas_web/live/mobile_live/dashboard.ex`
- Modify: `assets/js/dashboard_swipe.js`
- Test: `test/tugas_web/live/mobile_live/dashboard_test.exs`

**Interfaces:**
- Consumes: `urgent_panel/1` (Task 2, `variant={:mobile}`), `@urgent_rows` assign (Task 2).
- Produces: a 4-tab swipe deck `someday(0) | urgent(1) | calendar(2) | todo(3)`; the swipe hook reads the calendar index from `data-dashboard-calendar` on `#m-dashboard`.

- [ ] **Step 1: Write the failing test**

Add to `test/tugas_web/live/mobile_live/dashboard_test.exs`:

```elixir
test "urgent tab and panel render left of the calendar", %{conn: conn} do
  manager = Tugas.EntitiesFixtures.manager_scope_fixture()
  conn = log_in_user(conn, manager.user)
  type = type_fixture(manager.entity, reminder_offsets: "7")
  today = Urgency.today_for(manager.entity.timezone)

  {:ok, urgent} =
    Duties.create_duty(manager, %{
      title: "Overdue task",
      duty_type_id: type.id,
      due_by: Date.add(today, -1),
      open_note: "open"
    })

  {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

  assert has_element?(view, "#m-dashboard-go-urgent", "urgent")
  assert has_element?(view, "[data-dashboard-go='1']", "urgent")
  assert has_element?(view, "[data-dashboard-go='2']", "calendar")
  assert has_element?(view, "[data-dashboard-panel='1'] #m-dashboard-urgent")
  assert has_element?(view, "#m-dashboard-urgent #urgent-panel-duty-chip-#{urgent.id}")
end
```

Confirm the test file aliases `Tugas.Duties.Urgency` and imports `Tugas.DutiesFixtures` (the existing someday tests use `type_fixture`/`Duties.create_duty`, so these are already present; if `Urgency` is not aliased, add `alias Tugas.Duties.Urgency` at the top).

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/mobile_live/dashboard_test.exs -v`
Expected: FAIL — no `#m-dashboard-go-urgent` / `data-dashboard-go='1'` urgent element.

- [ ] **Step 3: Add the urgent tab + panel and reindex**

In `lib/tugas_web/live/mobile_live/dashboard.ex`:

Add `data-dashboard-calendar="2"` to the swipe root (line 63):

```elixir
        <div
          id="m-dashboard"
          phx-hook="DashboardSwipe"
          data-dashboard-calendar="2"
          class="flex min-h-0 flex-1 flex-col px-1 py-1 gap-1"
        >
```

Replace the tab strip (the `#m-dashboard-swipe-hint` block, lines 67–92) with four tabs:

```elixir
          <div id="m-dashboard-swipe-hint" class="tabs tabs-box w-full shrink-0">
            <button
              type="button"
              id="m-dashboard-go-someday"
              data-dashboard-go="0"
              class="tab flex-1 min-h-8 text-sm"
            >
              someday
            </button>
            <button
              type="button"
              id="m-dashboard-go-urgent"
              data-dashboard-go="1"
              class="tab flex-1 min-h-8 text-sm"
            >
              urgent
            </button>
            <button
              type="button"
              id="m-dashboard-go-calendar"
              data-dashboard-go="2"
              class="tab flex-1 min-h-8 text-sm tab-active font-bold"
            >
              calendar
            </button>
            <button
              type="button"
              id="m-dashboard-go-todos"
              data-dashboard-go="3"
              class="tab flex-1 min-h-8 text-sm"
            >
              todo
            </button>
          </div>
```

Insert the urgent panel as `data-dashboard-panel="1"` between the someday panel (panel 0) and the calendar panel, and renumber the calendar panel to `2` and the todos panel to `3`. The panels block becomes:

```elixir
          <div id="m-dashboard-panels" class="relative flex min-h-0 flex-1 flex-col">
            <div
              data-dashboard-panel="0"
              class="hidden min-h-0 flex-1 overflow-y-auto pr-2"
            >
              <.mobile_someday_panel
                rows={@someday_rows}
                slug={@current_scope.entity.slug}
                variant={:mobile}
              />
            </div>

            <div
              data-dashboard-panel="1"
              class="hidden min-h-0 flex-1 overflow-y-auto pr-2"
            >
              <.urgent_panel
                rows={@urgent_rows}
                slug={@current_scope.entity.slug}
                variant={:mobile}
              />
            </div>

            <div
              data-dashboard-panel="2"
              class="flex min-h-0 flex-1 flex-col overflow-hidden px-1"
            >
              <.duty_calendar
                variant={:mobile}
                hide_someday_strip?={true}
                grid={@grid}
                grouped={@grouped}
                someday_rows={@someday_rows}
                slug={@current_scope.entity.slug}
                day_modal_date={@day_modal_date}
                day_modal_rows={@day_modal_rows}
                day_modal_holidays={@day_modal_holidays}
                someday_modal_open?={@someday_modal_open?}
              />
            </div>

            <div
              data-dashboard-panel="3"
              class="hidden min-h-0 flex-1 overflow-y-auto pl-2"
            >
              <.dashboard_todos_panel
                variant={:mobile}
                todos={@todos}
                completed_todos={@completed_todos}
                slug={@current_scope.entity.slug}
                row_effects={@row_effects}
              />
            </div>
          </div>
```

- [ ] **Step 4: Make the swipe hook read the calendar index**

In `assets/js/dashboard_swipe.js`, in `mounted()` replace the hardcoded start index:

```javascript
  mounted() {
    this.panelsEl = this.el.querySelector("#m-dashboard-panels")
    this.calendarIndex = Number(this.el.dataset.dashboardCalendar ?? 1)
    this.panelIndex = this.calendarIndex
    this.touchStartX = null
    this.touchStartY = null
    this.swipeThreshold = 50
```

In `onTouchEnd()`, replace the guard `if (this.panelIndex !== 1) return` with:

```javascript
    if (this.panelIndex !== this.calendarIndex) return
```

(The hook is otherwise fully index-driven, so showing/hiding 4 panels needs no further change.)

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/tugas_web/live/mobile_live/dashboard_test.exs -v`
Expected: PASS (new test passes; the existing "tab panels render someday, calendar, and todos views" test still passes — calendar tab stays `tab-active`).

- [ ] **Step 6: Commit**

```bash
git add lib/tugas_web/live/mobile_live/dashboard.ex assets/js/dashboard_swipe.js test/tugas_web/live/mobile_live/dashboard_test.exs
git commit -m "feat(dashboard): add Urgent swipe panel left of the mobile calendar"
```

---

### Task 4: Docs + full verification

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: updated dashboard documentation; green `mix precommit`.

- [ ] **Step 1: Update CLAUDE.md**

In `CLAUDE.md`, in the "Dashboard = the attention surface" section, append a sentence to the paragraph describing the dashboard layout (after the Someday description):

```markdown
- **Most Urgent listing.** A focused column **left of the calendar** (desktop 3-col grid
  `[Urgent 15% | Calendar 1fr | Todos 15%]`; mobile a `someday | urgent | calendar | todo`
  swipe deck) lists live duties flagged for attention — `urgency in [:overdue, :due_soon]`,
  ranked overdue→due_soon then by `due_by`, via `CalendarHelpers.load_urgent_rows/3` (reuses
  `build_calendar_rows` + `Urgency.classify`, 1-year horizon, excludes dateless). Desktop caps
  at 10 chips with a `+N more` → `urgent-modal`; mobile scrolls. The Someday strip is unchanged.
```

- [ ] **Step 2: Run the full precommit**

Run: `mix precommit`
Expected: PASS — compiles with no warnings, formatted, full test suite green.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document the dashboard Most Urgent listing"
```

---

## Self-Review

**Spec coverage:**
- "What Most Urgent contains" (overdue + due-soon, ranked, per-type offsets) → Task 1.
- Desktop placement (3-col, left of calendar) → Task 2 Step 5.
- Cap + "+N more" modal → Task 2 Steps 4–5.
- Mobile placement (`someday | urgent | calendar | todo`, scrollable) → Task 3.
- Reused vs new table → Tasks 1–2.
- Testing (data filter/rank, desktop modal+empty, mobile tab/panel, regression) → Tasks 1–3.
- Edge cases (no urgent → empty state; Mine/Team reload; month ignored) → covered by `load_dashboard/1` wiring (Task 2) and empty-state copy (Task 2 Step 4).

**Placeholder scan:** No TBD/TODO; all steps contain concrete code and commands.

**Type consistency:** `load_urgent_rows/3`, `max_urgent_chips/0`, `urgent_rows`/`urgent_modal_open?` assigns, `urgent_panel/1` attrs (`rows`/`slug`/`variant`/`modal_open?`), and element ids (`urgent-panel`, `urgent-duty-chip-*`, `urgent-more`, `urgent-modal`, `urgent-modal-duty-chip-*`, `m-dashboard-urgent`, `urgent-panel-duty-chip-*`, `m-dashboard-go-urgent`) are used identically across tasks and tests.
