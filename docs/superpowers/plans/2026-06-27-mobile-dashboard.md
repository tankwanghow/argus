# Mobile dashboard calendar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/m/:slug` a calendar dashboard (live duties by due date, Someday strip, todos preview), move the paginated duty list to `/m/:slug/duties`, and add context-aware mobile bottom navigation.

**Architecture:** Extract shared calendar logic into `DashboardLive.IndexHelpers`; refactor desktop `DashboardLive.Index` to delegate. Add `variant` attrs to `DutyCalendar` and `DashboardTodosPanel` for mobile density/paths. Extract today's `MobileLive.Dashboard` list into `MobileLive.DutyIndex`. Replace `Layouts.mobile_bottom_nav` with `nav_context`-driven tab sets.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8.5 / LiveView 1.2.1 / Ecto 3.13 / PostgreSQL / Tailwind v4 + daisyUI 5.

**Spec:** `docs/superpowers/specs/2026-06-27-mobile-dashboard-design.md`.

## Global Constraints

- Desktop `DashboardLive.Index` behavior **unchanged** after refactor.
- Calendar shows **live duties only** (`:live` / `:my_live`).
- `today` via `Urgency.today_for(entity.timezone)` — never `Date.utc_today()`.
- Open todo preview limit **11**; completed preview limit **5** (shared with desktop).
- Mobile calendar: **2** chips/day, **6** someday chips before overflow.
- Every `Layouts.mobile_app` LiveView defines `handle_event("close_modal_on_escape", …)`.
- Unauthorized context calls return `:not_authorise`.
- Run `mix precommit` before declaring done.
- TDD: failing test → implement → pass → commit per task.

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/tugas_web/live/dashboard_live/index_helpers.ex` | Shared mount, load, event handlers |
| Modify | `lib/tugas_web/live/dashboard_live/index.ex` | Thin desktop LiveView delegating to helpers |
| Modify | `lib/tugas_web/components/duty_calendar.ex` | `variant` attr, mobile density, device paths |
| Modify | `lib/tugas_web/components/dashboard_todos_panel.ex` | `variant` attr, mobile layout/paths |
| Modify | `lib/tugas_web/components/layouts.ex` | Context-aware `mobile_bottom_nav` |
| Create | `lib/tugas_web/live/mobile_live/duty_index.ex` | Paginated duty list (old dashboard) |
| Modify | `lib/tugas_web/live/mobile_live/dashboard.ex` | Calendar home |
| Modify | `lib/tugas_web/router.ex` | Add `/m/:slug/duties` route; dashboard `:index` |
| Modify | `lib/tugas_web/live/mobile_live/*.ex` | `nav_context` on each mobile LiveView |
| Create | `test/tugas_web/live/mobile_live/dashboard_test.exs` | Calendar integration tests |
| Create | `test/tugas_web/live/mobile_live/duty_index_test.exs` | List smoke tests |
| Modify | `test/tugas_web/live/mobile_live_test.exs` | List tests → `/duties`; nav assertions |
| Modify | `test/tugas_web/plugs/auto_route_by_device_test.exs` | `/entities/:slug/duties` redirect |

---

### Task 1: Extract `DashboardLive.IndexHelpers`

**Files:**
- Create: `lib/tugas_web/live/dashboard_live/index_helpers.ex`
- Modify: `lib/tugas_web/live/dashboard_live/index.ex`
- Test: `test/tugas_web/live/dashboard_live_test.exs` (existing — must stay green)

**Interfaces:**
- Produces:
  - `mount_dashboard(socket, session) :: {:ok, socket}`
  - `handle_set_scope(socket, mine) :: socket`
  - `handle_prev_month(socket) :: socket`
  - `handle_next_month(socket) :: socket`
  - `handle_today(socket) :: socket`
  - `handle_open_day_modal(socket, iso) :: socket`
  - `handle_close_day_modal(socket) :: socket`
  - `handle_open_someday_modal(socket) :: socket`
  - `handle_close_someday_modal(socket) :: socket`
  - `handle_toggle_todo_complete(socket, id) :: socket`
  - `handle_finish_row_effect(socket, id) :: socket`
  - `handle_close_modal_on_escape(socket) :: socket`
  - `@open_preview_limit` → `11`
  - `@completed_preview_limit` → `5`

- [ ] **Step 1: Run existing desktop dashboard tests (baseline)**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs`
Expected: PASS (11 tests)

- [ ] **Step 2: Create `index_helpers.ex`**

Move all private functions and event logic from `index.ex` into the new module. Keep module attributes `@open_preview_limit 11` and `@completed_preview_limit 5` in helpers.

```elixir
defmodule TugasWeb.DashboardLive.IndexHelpers do
  @moduledoc false

  alias Tugas.Duties.Urgency
  alias Tugas.Todos
  alias Tugas.Todos.Todo
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DutiesFilter

  @open_preview_limit 11
  @completed_preview_limit 5

  def open_preview_limit, do: @open_preview_limit
  def completed_preview_limit, do: @completed_preview_limit

  def mount_dashboard(socket, session) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    {year, month} = Calendar.current_month(today)

    socket
    |> Phoenix.Component.assign(:today, today)
    |> Phoenix.Component.assign(:year, year)
    |> Phoenix.Component.assign(:month, month)
    |> Phoenix.Component.assign(:day_modal_date, nil)
    |> Phoenix.Component.assign(:day_modal_rows, [])
    |> Phoenix.Component.assign(:someday_modal_open?, false)
    |> Phoenix.Component.assign(:row_effects, %{})
    |> DutiesFilter.assign_filters(session)
    |> load_dashboard()
    |> then(&{:ok, &1})
  end

  def handle_set_scope(socket, mine) do
    socket
    |> Phoenix.Component.assign(:mine?, mine == "true")
    |> load_dashboard()
    |> DutiesFilter.persist()
  end

  def handle_prev_month(socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, -1)

    socket
    |> Phoenix.Component.assign(year: year, month: month)
    |> load_dashboard()
  end

  def handle_next_month(socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, 1)

    socket
    |> Phoenix.Component.assign(year: year, month: month)
    |> load_dashboard()
  end

  def handle_today(socket) do
    today = socket.assigns.today
    {year, month} = Calendar.current_month(today)

    socket
    |> Phoenix.Component.assign(year: year, month: month)
    |> load_dashboard()
  end

  def handle_open_day_modal(socket, iso) do
    date = Date.from_iso8601!(iso)
    rows = Map.get(socket.assigns.grouped, date, [])

    socket
    |> Phoenix.Component.assign(day_modal_date: date, day_modal_rows: rows)
    |> Phoenix.Component.assign(:someday_modal_open?, false)
  end

  def handle_close_day_modal(socket) do
    Phoenix.Component.assign(socket, day_modal_date: nil, day_modal_rows: [])
  end

  def handle_open_someday_modal(socket) do
    socket
    |> Phoenix.Component.assign(:someday_modal_open?, true)
    |> Phoenix.Component.assign(day_modal_date: nil, day_modal_rows: [])
  end

  def handle_close_someday_modal(socket) do
    Phoenix.Component.assign(socket, :someday_modal_open?, false)
  end

  def handle_toggle_todo_complete(socket, id) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        case Todos.toggle_complete(scope, todo) do
          {:ok, updated} ->
            effect = if Todo.completed?(updated), do: :completed, else: :updated

            socket =
              if Todo.completed?(updated) do
                Phoenix.Component.assign(socket, :todos, replace_todo(socket.assigns.todos, updated))
              else
                Phoenix.Component.assign(
                  socket,
                  :completed_todos,
                  replace_todo(socket.assigns.completed_todos, updated)
                )
              end

            put_row_effect(socket, updated.id, effect)

          _ ->
            socket
        end

      _ ->
        socket
    end
  end

  def handle_finish_row_effect(socket, id) do
    row_effects = Map.delete(socket.assigns.row_effects || %{}, id)

    socket
    |> Phoenix.Component.assign(:row_effects, row_effects)
    |> load_todos()
  end

  def handle_close_modal_on_escape(socket) do
    cond do
      socket.assigns.day_modal_date ->
        handle_close_day_modal(socket)

      socket.assigns.someday_modal_open? ->
        handle_close_someday_modal(socket)

      true ->
        socket
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
    |> Phoenix.Component.assign(grid: grid, grouped: grouped, someday_rows: someday_rows)
    |> load_todos()
  end

  defp load_todos(socket) do
    scope = socket.assigns.current_scope

    todos =
      case Todos.list_todos_page(scope, status: :open, limit: @open_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    completed_todos =
      case Todos.list_todos_page(scope, status: :completed, limit: @completed_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    socket
    |> Phoenix.Component.assign(:todos, todos)
    |> Phoenix.Component.assign(:completed_todos, completed_todos)
  end

  defp replace_todo(todos, %Todo{} = updated) do
    case Enum.find_index(todos, &(&1.id == updated.id)) do
      nil -> todos
      idx -> List.replace_at(todos, idx, updated)
    end
  end

  defp put_row_effect(socket, todo_id, effect) do
    Phoenix.Component.assign(
      socket,
      :row_effects,
      Map.put(socket.assigns.row_effects || %{}, todo_id, effect)
    )
  end
end
```

- [ ] **Step 3: Refactor `DashboardLive.Index` to delegate**

```elixir
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard

  def mount(_params, session, socket), do: Dashboard.mount_dashboard(socket, session)

  def handle_event("set_scope", %{"mine" => mine}, socket),
    do: {:noreply, Dashboard.handle_set_scope(socket, mine)}

  def handle_event("prev_month", _, socket),
    do: {:noreply, Dashboard.handle_prev_month(socket)}

  def handle_event("next_month", _, socket),
    do: {:noreply, Dashboard.handle_next_month(socket)}

  def handle_event("today", _, socket),
    do: {:noreply, Dashboard.handle_today(socket)}

  def handle_event("open_day_modal", %{"date" => iso}, socket),
    do: {:noreply, Dashboard.handle_open_day_modal(socket, iso)}

  def handle_event("close_day_modal", _, socket),
    do: {:noreply, Dashboard.handle_close_day_modal(socket)}

  def handle_event("open_someday_modal", _, socket),
    do: {:noreply, Dashboard.handle_open_someday_modal(socket)}

  def handle_event("close_someday_modal", _, socket),
    do: {:noreply, Dashboard.handle_close_someday_modal(socket)}

  def handle_event("toggle_todo_complete", %{"id" => id}, socket),
    do: {:noreply, Dashboard.handle_toggle_todo_complete(socket, id)}

  def handle_event("finish_row_effect", %{"id" => id}, socket),
    do: {:noreply, Dashboard.handle_finish_row_effect(socket, id)}

  def handle_event("close_modal_on_escape", _, socket),
    do: {:noreply, Dashboard.handle_close_modal_on_escape(socket)}
```

Remove all moved private functions from `index.ex`.

- [ ] **Step 4: Run desktop dashboard tests**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/dashboard_live/index_helpers.ex lib/tugas_web/live/dashboard_live/index.ex
git commit -m "Extract DashboardLive.IndexHelpers for shared calendar logic"
```

---

### Task 2: `DutyCalendar` and `DashboardTodosPanel` variants

**Files:**
- Modify: `lib/tugas_web/components/duty_calendar.ex`
- Modify: `lib/tugas_web/components/dashboard_todos_panel.ex`
- Modify: `lib/tugas_web/live/dashboard_live/calendar_helpers.ex` (optional chip limit helpers)
- Test: `test/tugas_web/live/dashboard_live_test.exs`

**Interfaces:**
- Produces:
  - `attr :variant, :atom, default: :desktop` on both components
  - `max_chips_per_day(variant)` → 3 desktop, 2 mobile
  - `max_someday_chips(variant)` → 10 desktop, 6 mobile
  - `duty_path(variant, slug, duty_id)` → `/entities/...` or `/m/...`

- [ ] **Step 1: Add variant chip limits to `CalendarHelpers`**

```elixir
  def max_chips_per_day(:mobile), do: 2
  def max_chips_per_day(_), do: @max_chips_per_day

  def max_someday_chips(:mobile), do: 6
  def max_someday_chips(_), do: @max_someday_chips
```

Update `DutyCalendar` to call `CalendarHelpers.max_chips_per_day(@variant)` instead of bare `max_chips_per_day/0` (keep existing `max_chips_per_day/0` delegating to desktop for backward compat).

- [ ] **Step 2: Update `DutyCalendar`**

Add `attr :variant, :atom, default: :desktop`.

Cell classes:
- desktop: `min-h-24`
- mobile: `min-h-14`

Chip in calendar cells (mobile): title only, `text-[10px]`.

Someday section (mobile): wrap chips in `div class="flex gap-1 overflow-x-auto flex-nowrap"`.

Path helper inside component:

```elixir
  defp duty_show_path(:mobile, slug, id), do: ~p"/m/#{slug}/duties/#{id}"
  defp duty_show_path(_, slug, id), do: ~p"/entities/#{slug}/duties/#{id}"
```

Use in `duty_chip` navigate attr.

- [ ] **Step 3: Update `DashboardTodosPanel`**

Add `attr :variant, :atom, default: :desktop`.

```elixir
  defp todos_index_path(:mobile, slug), do: ~p"/m/#{slug}/todos"
  defp todos_index_path(_, slug), do: ~p"/entities/#{slug}/todos"
```

Mobile layout changes:
- Root: `section` not `aside` when mobile; drop `h-full` height chain classes
- Open/completed lists: add `max-h-48 overflow-y-auto` on mobile
- Remove `flex-[2]` / `flex-[1]` split on mobile — stack naturally

Pass `variant={:desktop}` explicitly from desktop `DashboardLive.Index` (default is fine).

- [ ] **Step 4: Run desktop tests**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/components/duty_calendar.ex lib/tugas_web/components/dashboard_todos_panel.ex lib/tugas_web/live/dashboard_live/calendar_helpers.ex
git commit -m "Add desktop/mobile variants to calendar and todos panel components"
```

---

### Task 3: Context-aware mobile bottom nav

**Files:**
- Modify: `lib/tugas_web/components/layouts.ex`
- Test: `test/tugas_web/live/mobile_live/nav_test.exs` (create)

**Interfaces:**
- Produces:
  - `attr :nav_context, :atom, default: :calendar` on `mobile_app/1` (replaces `active`)
  - Tab sets `:calendar` (5), `:todos` (4), `:duties` (4)

- [ ] **Step 1: Write failing nav test**

Create `test/tugas_web/live/mobile_live/nav_test.exs`:

```elixir
defmodule TugasWeb.MobileLive.NavTest do
  use TugasWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "calendar context shows five tabs including calendar and duties list", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    slug = manager.entity.slug

    {:ok, view, _html} = live(conn, ~p"/m/#{slug}")

    assert has_element?(view, "#m-nav-new-todo[href='/m/#{slug}/todos/new']")
    assert has_element?(view, "#m-nav-todos[href='/m/#{slug}/todos']")
    assert has_element?(view, "#m-nav-new-duty[href='/m/#{slug}/duties/new']")
    assert has_element?(view, "#m-nav-duties[href='/m/#{slug}/duties']")
    assert has_element?(view, "#m-nav-calendar[href='/m/#{slug}']")
    refute has_element?(view, "#m-nav-more[href]")
  end

  test "todos context omits todos tab", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    slug = manager.entity.slug

    {:ok, view, _html} = live(conn, ~p"/m/#{slug}/todos")

    refute has_element?(view, "#m-nav-todos")
    assert has_element?(view, "#m-nav-duties[href='/m/#{slug}/duties']")
    assert has_element?(view, "#m-nav-calendar[href='/m/#{slug}']")
  end
end
```

(Calendar home test will fail until Task 4 — run nav todos test first in isolation, or accept calendar test fails until Task 4.)

- [ ] **Step 2: Implement `nav_context` in `layouts.ex`**

Replace `active` attr with `nav_context` on `mobile_app/1`. Rewrite `mobile_bottom_nav/1`:

```elixir
  @nav_sets %{
    calendar: [:new_todo, :todos, :new_duty, :duties, :more],
    todos: [:new_todo, :duties, :calendar, :more],
    duties: [:todos, :new_duty, :calendar, :more]
  }

  @nav_items %{
    new_todo: %{id: "m-nav-new-todo", icon: "✚", label: "Todo", path: fn slug -> ~p"/m/#{slug}/todos/new" end},
    todos: %{id: "m-nav-todos", icon: "📑", label: "Todos", path: fn slug -> ~p"/m/#{slug}/todos" end},
    new_duty: %{id: "m-nav-new-duty", icon: "✚", label: "Duty", path: fn slug -> ~p"/m/#{slug}/duties/new" end},
    duties: %{id: "m-nav-duties", icon: "💼", label: "Duties", path: fn slug -> ~p"/m/#{slug}/duties" end},
    calendar: %{id: "m-nav-calendar", icon: "📅", label: "Calendar", path: fn slug -> ~p"/m/#{slug}" end},
    more: %{id: "m-nav-more", icon: "☰", label: "More", type: :button}
  }
```

Render `grid-cols-5` or `grid-cols-4` from set length. Highlight active item by comparing current `nav_context` + slot (e.g. on `:todos` page, highlight nothing or highlight create on `:new`).

Temporarily keep compiling by mapping old `active` values to `nav_context` if needed during migration.

- [ ] **Step 3: Run nav test (todos context only)**

Run: `mix test test/tugas_web/live/mobile_live/nav_test.exs:LINE_OF_TODOS_TEST`
Expected: PASS for todos context

- [ ] **Step 4: Commit**

```bash
git add lib/tugas_web/components/layouts.ex test/tugas_web/live/mobile_live/nav_test.exs
git commit -m "Add context-aware mobile bottom navigation"
```

---

### Task 4: `MobileLive.DutyIndex` + router

**Files:**
- Create: `lib/tugas_web/live/mobile_live/duty_index.ex`
- Modify: `lib/tugas_web/router.ex`
- Modify: `test/tugas_web/live/mobile_live_test.exs` (point list tests at `/duties`)
- Create: `test/tugas_web/live/mobile_live/duty_index_test.exs`

**Interfaces:**
- Produces: `MobileLive.DutyIndex` — copy of current `MobileLive.Dashboard` list implementation
- Route: `live "/m/:entity_slug/duties", MobileLive.DutyIndex, :index` **before** `/duties/new` and `/duties/:id`

- [ ] **Step 1: Write duty index smoke test**

```elixir
defmodule TugasWeb.MobileLive.DutyIndexTest do
  use TugasWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
  setup :register_and_log_in_user

  test "duty list renders at /m/:slug/duties", %{conn: conn} do
    {scope, duty} = assigned_member_scope_fixture()
    conn = conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/duties")

    assert has_element?(view, "#mobile-duties")
    assert has_element?(view, "#m-ob-#{duty.id}")
  end
end
```

- [ ] **Step 2: Run test — verify FAIL**

Run: `mix test test/tugas_web/live/mobile_live/duty_index_test.exs`
Expected: FAIL (no route / no module)

- [ ] **Step 3: Create `duty_index.ex`**

Copy entire current `lib/tugas_web/live/mobile_live/dashboard.ex` into `duty_index.ex`. Rename module to `TugasWeb.MobileLive.DutyIndex`. Change:

```elixir
<Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:duties}>
```

Keep sticky toolbar + stream list unchanged.

- [ ] **Step 4: Add router entry**

In `router.ex` mobile block:

```elixir
      live "/m/:entity_slug", MobileLive.Dashboard, :index
      live "/m/:entity_slug/duties", MobileLive.DutyIndex, :index
      live "/m/:entity_slug/duties/new", MobileLive.DutyForm, :new
      live "/m/:entity_slug/duties/:id", MobileLive.DutyShow, :show
```

Change dashboard from `:show` to `:index`.

- [ ] **Step 5: Run duty index test**

Run: `mix test test/tugas_web/live/mobile_live/duty_index_test.exs`
Expected: PASS

- [ ] **Step 6: Update `mobile_live_test.exs` list tests**

Change `live(conn, ~p"/m/#{scope.entity.slug}")` to `~p"/m/#{scope.entity.slug}/duties"` for tests asserting:
- filter restore (`#m-duty-search`, `#m-scope-mine`)
- `#mobile-duties` stream
- sort / load_more
- duty cards on list

Update bottom-nav test: duties list link is `#m-nav-duties[href='.../duties']`.

- [ ] **Step 7: Run affected mobile tests**

Run: `mix test test/tugas_web/live/mobile_live_test.exs test/tugas_web/live/mobile_live/duty_index_test.exs`
Expected: PASS (calendar home tests may still fail)

- [ ] **Step 8: Commit**

```bash
git add lib/tugas_web/live/mobile_live/duty_index.ex lib/tugas_web/router.ex test/tugas_web/live/mobile_live/duty_index_test.exs test/tugas_web/live/mobile_live_test.exs
git commit -m "Extract mobile duty list to MobileLive.DutyIndex at /m/:slug/duties"
```

---

### Task 5: Mobile calendar dashboard

**Files:**
- Modify: `lib/tugas_web/live/mobile_live/dashboard.ex` (rewrite)
- Create: `test/tugas_web/live/mobile_live/dashboard_test.exs`
- Modify: `test/tugas_web/live/mobile_live/nav_test.exs`

**Interfaces:**
- Consumes: `DashboardLive.IndexHelpers`, `DutyCalendar`, `DashboardTodosPanel` with `variant={:mobile}`

- [ ] **Step 1: Write failing mobile calendar tests**

Create `test/tugas_web/live/mobile_live/dashboard_test.exs` — port core cases from `dashboard_live_test.exs` with mobile paths and `@mobile_ua`:

```elixir
  test "renders calendar", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")
    assert has_element?(view, "#duty-calendar")
    assert has_element?(view, "#dashboard-todos")
  end

  test "duty chip links to mobile show", %{conn: conn} do
    # create duty with due date, assert chip href contains /m/.../duties/
  end

  test "toggle todo complete and backfill", %{conn: conn} do
    # same 12-todo backfill pattern as desktop test (limit 11)
  end
```

Include: someday strip, day overflow, reopen completed todo.

- [ ] **Step 2: Run tests — verify FAIL**

Run: `mix test test/tugas_web/live/mobile_live/dashboard_test.exs`
Expected: FAIL

- [ ] **Step 3: Rewrite `MobileLive.Dashboard`**

```elixir
defmodule TugasWeb.MobileLive.Dashboard do
  use TugasWeb, :live_view

  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard

  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:calendar}>
      <div class="sticky top-0 z-30 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200 space-y-2">
        <h1 class="flex items-center gap-2 text-lg font-semibold truncate">
          <.brand_logo class="size-9" /> Calendar -
          <span class="text-base-content/50">{@current_scope.entity.slug}</span>
        </h1>
        <div id="dashboard-scope-toggle" class="tabs tabs-box">
          <!-- Mine / Team buttons — same phx-click set_scope as desktop -->
        </div>
        <div class="flex items-center gap-1">
          <!-- prev month, label, next month, today -->
        </div>
      </div>

      <div id="m-dashboard" class="px-4 py-4 space-y-4">
        <.duty_calendar
          variant={:mobile}
          grid={@grid}
          grouped={@grouped}
          someday_rows={@someday_rows}
          slug={@current_scope.entity.slug}
          day_modal_date={@day_modal_date}
          day_modal_rows={@day_modal_rows}
          someday_modal_open?={@someday_modal_open?}
        />
        <.dashboard_todos_panel
          variant={:mobile}
          todos={@todos}
          completed_todos={@completed_todos}
          slug={@current_scope.entity.slug}
          row_effects={@row_effects}
        />
      </div>
    </Layouts.mobile_app>
    """
  end

  def mount(params, session, socket), do: Dashboard.mount_dashboard(socket, session)

  # delegate all handle_event clauses to Dashboard helpers — identical to desktop Index
end
```

- [ ] **Step 4: Run mobile dashboard + nav tests**

Run: `mix test test/tugas_web/live/mobile_live/dashboard_test.exs test/tugas_web/live/mobile_live/nav_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/mobile_live/dashboard.ex test/tugas_web/live/mobile_live/dashboard_test.exs test/tugas_web/live/mobile_live/nav_test.exs
git commit -m "Add mobile calendar dashboard at /m/:slug"
```

---

### Task 6: Update remaining mobile LiveViews `nav_context`

**Files:**
- Modify: `lib/tugas_web/live/mobile_live/todos.ex`
- Modify: `lib/tugas_web/live/mobile_live/duty_form.ex`
- Modify: `lib/tugas_web/live/mobile_live/duty_show.ex`
- Modify: `lib/tugas_web/live/mobile_live/duty_types.ex`
- Modify: `lib/tugas_web/live/mobile_live/members.ex`
- Modify: `lib/tugas_web/live/mobile_live/todo_team_log.ex`
- Modify: `lib/tugas_web/live/mobile_live/invite_session.ex`

- [ ] **Step 1: Replace `active={...}` with `nav_context`**

| Module | `nav_context` |
|--------|---------------|
| `Todos` `:index` | `:todos` |
| `Todos` `:new` | `:calendar` |
| `DutyIndex` | `:duties` |
| All others | `:calendar` |

Remove deprecated `active` attr from `mobile_app` if no callers remain.

- [ ] **Step 2: Run full mobile + dashboard test suites**

Run: `mix test test/tugas_web/live/mobile_live_test.exs test/tugas_web/live/mobile_live/ test/tugas_web/live/dashboard_live_test.exs`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add lib/tugas_web/live/mobile_live/
git commit -m "Wire nav_context on all mobile LiveViews"
```

---

### Task 7: AutoRoute test + precommit

**Files:**
- Modify: `test/tugas_web/plugs/auto_route_by_device_test.exs`

- [ ] **Step 1: Add redirect test for duty list**

```elixir
  test "redirects desktop duties list to mobile duty index" do
    conn =
      build_conn()
      |> put_req_header("user-agent", @mobile_ua)
      |> get("/entities/acme/duties")

    assert redirected_to(conn) == "/m/acme/duties"
  end
```

- [ ] **Step 2: Run plug test**

Run: `mix test test/tugas_web/plugs/auto_route_by_device_test.exs`
Expected: PASS

- [ ] **Step 3: Run precommit**

Run: `mix precommit`
Expected: PASS (all tests, format, warnings)

- [ ] **Step 4: Commit**

```bash
git add test/tugas_web/plugs/auto_route_by_device_test.exs
git commit -m "Test mobile redirect for entity duties list path"
```

---

## Spec Coverage Checklist

| Spec requirement | Task |
|------------------|------|
| Calendar home `/m/:slug` | Task 5 |
| Duty list `/m/:slug/duties` | Task 4 |
| Context-aware nav (3 hubs) | Task 3, 6 |
| Calendar hub on secondary pages | Task 6 |
| Mobile calendar density | Task 2 |
| Mobile someday horizontal scroll | Task 2 |
| Todos preview + backfill | Task 1, 5 |
| Shared IndexHelpers | Task 1 |
| Desktop unchanged | Task 1, 2 |
| AutoRoute `/duties` | Task 7 |