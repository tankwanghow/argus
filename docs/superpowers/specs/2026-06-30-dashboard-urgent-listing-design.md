# Dashboard "Most Urgent" Listing — Design

**Date:** 2026-06-30
**Status:** Approved (pending spec review)

## Goal

Add a **Most Urgent** duties listing to both the desktop and mobile dashboards, placed
to the **left of the calendar**. It surfaces the live duties that actually need attention
right now — **overdue first, then due-soon** — ranked, so the calendar's prime real estate
is flanked by a focused "act on these" column.

The existing **Someday** section (the dateless-duty strip/panel) is **kept unchanged**; this
is a new, separate section, not a replacement.

## Scope

- Desktop dashboard: `TugasWeb.DashboardLive.Index` (calendar view at `/entities/:slug`).
- Mobile dashboard: `TugasWeb.MobileLive.Dashboard` (swipe deck at `/m/:slug`).
- Shared data/loading: `TugasWeb.DashboardLive.CalendarHelpers` and
  `TugasWeb.DashboardLive.IndexHelpers`.
- Rendering: `TugasWeb.DutyCalendar` (or a small sibling component) for the panel + modal.

Out of scope: the duty-list page's existing `urgency` sort (unchanged), any new urgency
math (we reuse `Tugas.Duties.Urgency` as-is), notifications.

## What "Most Urgent" contains

Only duties flagged for attention — **`urgency in [:overdue, :due_soon]`** — ranked
`overdue → due_soon`, then by `due_by` ascending. Duties that are merely `:ok` (nothing
due soon) and dateless (`:none`) duties are excluded; the latter still live in the Someday
section.

"Due soon" is per each duty type's `reminder_offsets` (e.g. a `"90,30,7,1"` type counts as
due-soon 90 days out), exactly as `Urgency.classify/3` already computes it.

### Data loading

New helper in `CalendarHelpers`:

```elixir
@urgent_window_days 365

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

Notes:
- `due_before: horizon` excludes dateless duties (null `due_by`) — correct, they are never
  urgent. Overdue duties (past `due_by`) are included since they're below the upper bound.
- The 1-year horizon mirrors `DutyLive.IndexHelpers`' existing `@urgency_window_days`; a type
  with a reminder offset beyond 365 days is an accepted edge case (same assumption already
  in place for the duty-list `urgency` sort).
- Reuses `Index.build_calendar_rows/2`, so each row already carries `urgency` + `tier` for the
  chip's countdown badge and accent border.

### Wiring

`IndexHelpers.load_dashboard/1` gains `urgent_rows = Calendar.load_urgent_rows(scope, today, mine?)`
and assigns `:urgent_rows`. Because it's part of `load_dashboard/1`, it refreshes on the
Mine/Team toggle and month navigation (it ignores the month — urgency is "now"-relative). An
`:urgent_modal_open?` assign (default `false`) backs the overflow modal.

## Desktop placement (left of the calendar)

Current grid: `grid-cols-[minmax(0,1fr)_15%]` (calendar | todos). New grid is three columns:

```
grid-cols-1 lg:grid-cols-[15%_minmax(0,1fr)_15%]
[ Urgent 15% | Calendar 1fr | Todos 15% ]
```

The calendar stays the dominant center column; Todos stays on the right; the new **Urgent**
column is on the left. The Someday strip remains under the calendar, untouched.

### Overflow: cap + "+N more" modal

The Urgent column shows up to `max_urgent_chips` chips (desktop **10**), then a **"+N more"**
button that opens an **urgent modal** listing the full ranked set — mirroring the existing
Someday strip's `+N more` → `someday_modal` pattern. New events:
`open_urgent_modal` / `close_urgent_modal`, handled in both LiveViews via `IndexHelpers`,
and folded into `handle_close_modal_on_escape/1`.

## Mobile placement

Mobile is a swipe deck driven by the `DashboardSwipe` hook, with tab buttons
(`data-dashboard-go`) and panels (`data-dashboard-panel`) indexed `0..N`. Add an **Urgent**
tab/panel **directly left of the calendar**, giving the order:

```
someday(0) | urgent(1) | calendar(2) | todo(3)
```

All `data-dashboard-go` / `data-dashboard-panel` indices shift to `0..3`; the
`DashboardSwipe` hook must be confirmed to handle an arbitrary panel count (it is index-driven,
so this is expected to be a data change only — verified during implementation).

The mobile Urgent panel is a **full-screen scrollable list** of the ranked urgent chips
(consistent with the existing mobile Someday panel, which scrolls rather than capping). The
cap + "+N more" modal applies to the **desktop side column only**, where vertical space is
limited; the mobile full-screen panel scrolls. Empty state: "Nothing overdue or due soon."

## Components

- `urgent_panel/1` — the rendered listing. Desktop variant: capped chips + "+N more". Mobile
  variant: scrollable full list. Modeled on `dashboard_todos_panel/1` and
  `mobile_someday_panel/1`. Reuses `duty_chip` for each row (so countdown badge + tier border
  are consistent with the calendar and Someday chips).
- `urgent_modal/1` — desktop overflow modal listing the full ranked set; modeled on
  `someday_modal/1`.

## Reused vs. new

| Reused | New |
|--------|-----|
| `Urgency.classify/tier` | `CalendarHelpers.load_urgent_rows/3` + `urgent_rank/1` |
| `Index.build_calendar_rows/2` | `:urgent_rows` / `:urgent_modal_open?` assigns in `IndexHelpers` |
| `Duties.list_calendar_duties/2` | `urgent_panel/1` + `urgent_modal/1` components |
| `duty_chip` styling | desktop 3-col grid; mobile 4th swipe panel |
| `someday_modal`/strip patterns | `open_urgent_modal`/`close_urgent_modal` events |

## Testing

- `CalendarHelpers.load_urgent_rows/3`: includes overdue + due-soon, excludes `:ok` and
  dateless; ranks overdue before due-soon, then by `due_by`; respects Mine/Team status;
  `:not_authorise` → `[]`.
- LiveView (desktop): Urgent column renders ranked chips left of the calendar; "+N more"
  opens/closes the urgent modal; Escape closes it; empty state shown when none.
- LiveView (mobile): Urgent tab/panel present between someday and calendar; swipe indices
  intact; scrollable list; empty state.
- Regression: Someday strip/panel and the calendar still render unchanged.

## Edge cases

- No urgent duties → empty-state copy, no "+N more", no modal.
- A duty whose type offset exceeds 365 days won't appear until within the horizon (accepted,
  matches existing duty-list urgency behavior).
- Mine/Team toggle and month nav both reload the urgent rows; month is ignored for ranking.
