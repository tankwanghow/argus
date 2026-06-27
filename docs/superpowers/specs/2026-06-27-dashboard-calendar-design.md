# Desktop dashboard calendar — design

**Date:** 2026-06-27  
**Status:** Approved (pending spec review)  
**Surface:** `DashboardLive.Index` (Desktop only). Mobile dashboard unchanged in this iteration.

## Problem

The entity home route (`/entities/:entity_slug`) is a placeholder ("Dashboard coming soon").
The real duty attention surface today is the paginated list at `/entities/:slug/duties`
(`DutyLive.Index`), which must stay unchanged.

Users want a **new desktop dashboard** that gives a calendar overview of live duties (by due date
and urgency) plus a compact todos preview — without altering the existing Duties page.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Duties on calendar | **Live only** (`:live` / `:my_live` status) |
| Calendar layout | **Month grid** (Sun–Sat) + **Someday strip** for dateless live duties |
| Todos panel | **Compact preview** — up to 15 open todos, checkbox complete, "View all →" link |
| Duties list page | **Unchanged** — `DutyLive.Index` at `/duties` keeps all filters, search, pagination |
| Navbar | **Add** "Dashboard" item; **Duties** link stays on `/duties` |
| Scope | **Mine / Team** toggle on dashboard; shares `mine?` persistence via `DutiesFilter` |
| Mobile | Out of scope — `MobileLive.Dashboard` stays as the duty list |

## Navigation

Desktop entity nav becomes four items:

```
📅 Dashboard  ·  💼 Duties  ·  📑 Todos  ·  🏷️ Types
```

| Link | Route | Module |
|------|-------|--------|
| Dashboard (new) | `/entities/:slug` | `DashboardLive.Index` |
| Duties (unchanged) | `/entities/:slug/duties` | `DutyLive.Index` |
| Todos | `/entities/:slug/todos` | `TodoLive.Index` |
| Types | `/entities/:slug/duty-types` | `DutyTypeLive.Index` |

- Brand logo and entity picker entry path remain `/entities/:slug` (dashboard home).
- No "List view" link on the dashboard — the Duties nav item is sufficient.
- `AutoRouteByDevice` whitelist for `/entities/:slug` is already in place.

## Layout

The dashboard needs more horizontal space than other entity pages. Add an optional `container_class`
attr to `Layouts.app/1` (default `max-w-4xl`); the dashboard passes `max-w-7xl`. All other pages
keep the default.

Two-column page structure inside `DashboardLive.Index`:

```
┌──────────────────────────────────────────┬─────────────┐
│ Toolbar: Mine/Team · ‹ Jun 2026 › · Today│   Todos     │
├──────────────────────────────────────────┤  (sidebar)  │
│ Sun Mon Tue Wed Thu Fri Sat              │             │
│ [month grid — duty chips per due date]   │  ☐ Todo 1   │
├──────────────────────────────────────────┤  ☐ Todo 2   │
│ Someday: [dateless live duty chips]      │  View all → │
└──────────────────────────────────────────┴─────────────┘
```

Approximate split: calendar column ~65–70%, todos sidebar ~30% (`max-w-sm`), responsive — on
viewports below `lg`, stack todos below the calendar (calendar first).

## Calendar behavior

### Month grid

- Classic 7-column week grid (Sun–Sat headers).
- Shows the selected month plus leading/trailing days from adjacent months (muted styling).
- **Initial month:** month containing `today`, where `today = Urgency.today_for(entity.timezone)`.
- **Today cell:** subtle ring or background highlight.
- **Navigation:** `‹` prev month, `›` next month, **Today** button jumps back to the current month.
- Month label in toolbar (e.g. "June 2026").

### Duty chips

Each live duty with a `due_by` in the visible month appears as a compact chip on that date:

- **Title** (truncated, e.g. `max-w-full truncate`)
- **Type name** as muted secondary text (`duty_type.name`)
- **Urgency tier** via existing `UrgencyBadge.tier_border/1` as a left border on the chip:
  `error` → `error/60` → `warning` → `warning/40` → `transparent` (for `:ok` / no urgency)
- Click navigates to `/entities/:slug/duties/:id`
- Chips sorted within a day by `due_by` then title (all same date, so title A–Z)

### Overflow

When a day has more than **3** duties, render the first 3 chips plus a **"+N more"** control.
Clicking "+N more" opens a small modal (or popover) listing all duties for that day with the same
chip styling. Modal closes on Escape via `close_modal_on_escape` / `ModalEscape` pattern.

### Scope toggle

- Mine / Team tabs (same visual pattern as `DutyLive.Index`).
- Reuses `DutiesFilter.assign_filters/2` for `mine?` on mount and `DutiesFilter.persist/1` on toggle.
- Maps to `IndexHelpers.status_atom(mine?, :live)` → `:live` or `:my_live`.
- Lifecycle, sort, and search filters from the duties list are **not** on the dashboard.

## Someday strip

Below the calendar, a horizontal section titled **"Someday"**:

- Live duties with `due_by IS NULL` (same Mine/Team scope).
- Rendered as the same chip component (no date).
- Sorted title A–Z.
- Section hidden when empty (no heading clutter).
- Chips link to duty show page.

## Todos sidebar

Right column panel titled **"Todos"**:

- Load up to **15** open todos via `Todos.list_todos_page(scope, status: :open, limit: 15)`.
- Each row: checkbox + truncated title.
- Checkbox calls `Todos.toggle_complete/2` (complete or reopen).
- On complete, row removes from sidebar list (or animates out); no edit/cancel/history.
- **"View all →"** link to `/entities/:slug/todos`.
- No "New todo" on dashboard — creation stays on the todos page.
- Empty state: "No open todos." with link to todos page.

## Architecture

### Modules

| Module | Responsibility |
|--------|----------------|
| `DashboardLive.Index` | mount, events (`prev_month`, `next_month`, `today`, `set_scope`, `toggle_todo_complete`, `open_day_modal`, `close_day_modal`, `close_modal_on_escape`), render |
| `DashboardLive.CalendarHelpers` | Build month grid cells, group duties by date, compute row maps via `IndexHelpers.build_rows/2`, someday list |
| `TugasWeb.DutyCalendar` | Function component: month grid + someday strip + day overflow modal |
| `TugasWeb.DashboardTodosPanel` | Function component: sidebar todos list |

### Reused (no changes unless noted)

- `TugasWeb.DutyLive.IndexHelpers` — `build_rows/2`, `default_mine?/1`, `status_atom/2`
- `TugasWeb.UrgencyBadge` — `tier_border/1`
- `TugasWeb.DutiesFilter` — `mine?` persistence only
- `Tugas.Duties.Urgency` — `today_for/1`, `tier/3`
- `DutyLive.Index` — **zero changes**

### Data loading

**Month duties (dated):**

Query live duties whose `due_by` falls in `[month_start, month_end]` (inclusive), respecting
Mine/Team scope. Prefer extending `Duties.list_duties/2` with optional `:due_before` and
`:due_after` keyword args (mirroring `list_duties_page/2`'s `apply_due_bound/3`) so the dashboard
does not load the full live set into memory. Preload `:duty_type` and `:primary_assignee`.

```elixir
Duties.list_duties(scope,
  status: status_atom(mine?, :live),
  due_after: Date.add(month_start, -1),   # exclusive lower bound → due_by >= month_start
  due_before: month_end
)
```

(Exact bound helpers live in `CalendarHelpers`; use `due_by >= month_start AND due_by <= month_end`.)

**Someday duties:**

```elixir
Duties.list_duties(scope, status: status_atom(mine?, :live))
|> Enum.filter(&is_nil(&1.due_by))
|> Enum.sort_by(&String.downcase(&1.title))
```

Or a SQL `where(is_nil(o.due_by))` via the same `list_duties` extension.

**Todos:**

```elixir
Todos.list_todos_page(scope, status: :open, limit: 15)
```

Returns `{:ok, %{rows: todos, ...}}` or `:not_authorise`.

**Row enrichment:**

Pass duty lists through `IndexHelpers.build_rows(duties, today)` to attach `tier`, `urgency`,
`cycle_status`, and event meta (event meta not rendered on chips — only tier border matters).

### CalendarHelpers API (sketch)

```elixir
def build_month_grid(year, month, today) :: %{weeks: [[cell]]}
# cell = %{date: Date, in_month?: boolean, today?: boolean}

def group_by_date(rows) :: %{Date.t() => [row]}

def month_range(year, month) :: {month_start, month_end}
```

Grid includes trailing/leading days so the week rows are complete (typically 5–6 rows).

### LiveView events

| Event | Behavior |
|-------|----------|
| `set_scope` | Toggle `mine?`, reload duties + someday, persist via `DutiesFilter` |
| `prev_month` | Decrement `@year`/`@month`, reload month duties |
| `next_month` | Increment `@year`/`@month`, reload month duties |
| `today` | Reset to current month, reload |
| `open_day_modal` | Set `@day_modal_date` + duties for that day |
| `close_day_modal` | Clear day modal assign |
| `toggle_todo_complete` | `Todos.toggle_complete/2`, refresh sidebar list |
| `close_modal_on_escape` | Close day modal if open (no-op otherwise) |

Month state stored as `@year` + `@month` integers (or a single `@view_month` Date at day 1).

## UI components

### Duty chip (shared)

Small clickable element used in calendar cells and someday strip:

```heex
<.link navigate={~p"/entities/#{@slug}/duties/#{@row.duty.id}"} class={[
  "block text-xs px-1.5 py-0.5 rounded border-l-2 truncate",
  tier_border(@row.tier)
]}>
  <span class="font-medium">{@row.duty.title}</span>
  <span class="text-base-content/50 ml-1">{@row.duty.duty_type.name}</span>
</.link>
```

Live duties always have a tier when `due_by` is set; dateless duties get `:none` tier
(`border-transparent`).

### Layouts change

```elixir
attr :container_class, :string, default: "max-w-4xl"
```

Applied to the `<div class="mx-auto ...">` wrapper in `Layouts.app/1`.

### Entity nav change

Add first link in `entity_nav/1`:

```heex
<.entity_nav_link
  href={~p"/entities/#{@current_scope.entity.slug}"}
  label="📅 Dashboard"
/>
```

Existing Duties / Todos / Types links unchanged.

## Testing

Replace `dashboard_live_test.exs` placeholder tests with:

1. **Renders calendar** — current month label, 7 day-of-week headers, today highlight.
2. **Duty on correct date** — fixture with known `due_by` appears in that cell.
3. **Urgency border** — overdue duty chip has `border-error` (or equivalent tier class).
4. **Someday strip** — dateless live duty appears in someday section, not on grid.
5. **Mine/Team** — toggling scope filters duties (member sees only assigned when Mine).
6. **Month navigation** — prev/next changes visible month label and duty placement.
7. **Todos sidebar** — open todo title visible; "View all" link present.
8. **Toggle todo complete** — checkbox completes todo, row disappears from sidebar.
9. **Day overflow** — 4+ duties on one day shows "+N more"; modal lists all.
10. **Nav** — entity nav includes Dashboard link pointing to `/entities/:slug`.

Existing `duty_live` tests must pass unchanged.

## Out of scope

- Any change to `DutyLive.Index`, `/duties` route, or `DutiesFilter` lifecycle/sort/search behavior
- Mobile dashboard calendar redesign
- Search or lifecycle filters on the dashboard calendar
- Full todos CRUD on the dashboard (create, edit, cancel, history, team log)
- Week view, drag-and-drop rescheduling, or iCal export
- Background jobs or notifications

## Implementation notes

- Follow TDD: failing LiveView test → implement → `mix precommit`.
- One commit per logical task if using the plan's commit-per-task rhythm.
- `close_modal_on_escape` is required by the shell contract (`#tugas-shell`).