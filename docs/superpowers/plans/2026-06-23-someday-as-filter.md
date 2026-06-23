# Someday as an orthogonal "Due date" filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Someday" (dateless) an orthogonal **Due date** filter (`dated`/`someday`/`all_dates`) that combines with any lifecycle, instead of a lifecycle value.

**Architecture:** Add a `date_scope` filter to the query (orthogonal to status), retire the `:someday` lifecycle/status, and add a "Due date" dropdown to both dashboards. Sort options become `(lifecycle × date_filter)`-aware. All dateless-duty machinery (schema, create/edit toggle, recurrence guard, urgency `:none`, render guards) is untouched.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8.5 / LiveView 1.2.1 / Ecto 3.13 / PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-06-23-someday-as-filter-design.md`.

## Global Constraints

- `date_filter` values: `dated | someday | all_dates`, default **`dated`**. SQL: `:dated → due_by IS NOT NULL`, `:someday → due_by IS NULL`, `:all_dates → no constraint`.
- Lifecycle values revert to `live · completed · skipped · all` (no `someday`). Core `live/1` unchanged.
- Sort offered when: **urgency** iff `lifecycle==:live AND date_filter==:dated`; **recent** iff `date_filter==:someday` (default there); **due_asc/due_desc** iff `date_filter in [:dated,:all_dates]`; **title** always. Non-offered persisted sort coerces to the combo default (`:someday→:recent`, else `:due_asc`).
- The NULLS-LAST nullable-`due_by` keyset and the `:recent` sort stay.
- Row rendering is unchanged (dateless rows already hide due/urgency chrome).
- Run `mix precommit` before declaring done. Commit bodies end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## File Structure

- Modify: `lib/argus/obligations.ex` — drop `:someday`/`:my_someday` status; add `apply_date_scope/2` + `:date_scope` opt; remove `apply_page_status/2`.
- Modify: `lib/argus_web/live/obligation_live/index_helpers.ex` — remove someday-lifecycle vocab; add `date_filters/0`, `parse_date_filter/1`, `sorts/2`, `effective_sort/3`, `empty_message/3`, `load_page/8` (+ a `load_page/7` shim defaulting `:dated`).
- Modify: `lib/argus_web/dashboard_filter.ex` — persist `date_filter`; drop `someday` from the lifecycle whitelist.
- Modify: `lib/argus_web/live/dashboard_live/index.ex` + `lib/argus_web/live/mobile_live/dashboard.ex` — "Due date" dropdown, `set_date_filter`, thread `@date_filter`, `sorts/2`.
- Tests: `test/argus/obligations_test.exs`, `test/argus_web/live/index_helpers_test.exs`, `test/argus_web/dashboard_filter_test.exs`, `test/argus_web/live/dashboard_live_test.exs`, `test/argus_web/live/mobile_live_test.exs`.

---

### Task 1: Query + IndexHelpers engine — `date_scope` replaces `:someday` lifecycle

**Files:**
- Modify: `lib/argus/obligations.ex`
- Modify: `lib/argus_web/live/obligation_live/index_helpers.ex`
- Test: `test/argus/obligations_test.exs`, `test/argus_web/live/index_helpers_test.exs`, `test/argus_web/live/dashboard_live_test.exs`, `test/argus_web/live/mobile_live_test.exs`

**Interfaces:**
- Produces:
  - `list_obligations_page(scope, opts)` — `opts` drops `:someday`/`:my_someday` status; gains `:date_scope` (`:dated | :someday | :all_dates`, default `:all_dates`). `@status_filters` back to `~w(my_live my_completed my_skipped my_all live completed skipped all)a`.
  - `IndexHelpers.date_filters/0 :: [{"dated","Has due date"},{"someday","Someday"},{"all_dates","All dates"}]`; `parse_date_filter/1`; `sorts(lifecycle, date_filter)`; `effective_sort(sort, lifecycle, date_filter)`; `empty_message(mine?, lifecycle, date_filter)`; `load_page(scope, today, mine?, lifecycle, date_filter, query, sort, cursor)` plus a `load_page/7` shim that delegates with `:dated`.

- [ ] **Step 1: Update the obligations query tests to the new API (RED)**

In `test/argus/obligations_test.exs`, replace the `describe "list_obligations_page/2 — someday + nullable keyset"` block body so it uses `status` + `date_scope` instead of the `:someday` status. Use this exact block:

```elixir
  describe "list_obligations_page/2 — date_scope" do
    setup do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      dated =
        for {t, d} <- [{"Dated A", ~D[2026-02-01]}, {"Dated B", ~D[2026-03-01]}] do
          {:ok, o} = Obligations.create_obligation(manager, %{title: t, obligation_type_id: type.id, due_by: d, open_note: "n"})
          o
        end

      someday =
        for t <- ["Someday X", "Someday Y", "Someday Z"] do
          {:ok, o} = Obligations.create_obligation(manager, %{title: t, obligation_type_id: type.id, someday: true, open_note: "n"})
          o
        end

      %{manager: manager, dated: dated, someday: someday}
    end

    test "date_scope :dated and :someday split live duties", %{manager: m, dated: dated, someday: someday} do
      d = Obligations.list_obligations_page(m, status: :live, date_scope: :dated, limit: :all)
      assert Enum.map(d.rows, & &1.id) |> Enum.sort() == Enum.map(dated, & &1.id) |> Enum.sort()

      s = Obligations.list_obligations_page(m, status: :live, date_scope: :someday, sort: :recent, limit: :all)
      assert Enum.map(s.rows, & &1.id) |> Enum.sort() == Enum.map(someday, & &1.id) |> Enum.sort()
    end

    test "date_scope :all_dates returns both", %{manager: m, dated: dated, someday: someday} do
      a = Obligations.list_obligations_page(m, status: :live, date_scope: :all_dates, limit: :all)
      assert length(a.rows) == length(dated) + length(someday)
    end

    test "date_scope composes with a non-live lifecycle (completed someday)", %{manager: m, someday: [sx | _]} do
      {:ok, _, _} = Obligations.complete(m, sx, %{note: "d"})
      page = Obligations.list_obligations_page(m, status: :completed, date_scope: :someday, sort: :recent, limit: :all)
      assert Enum.map(page.rows, & &1.id) == [sx.id]
    end

    test "my_* + date_scope :someday scopes to the user", %{manager: m} do
      member = member_scope_on_entity(m.entity)
      type = type_fixture(m.entity)
      {:ok, mine} = Obligations.create_obligation(m, %{title: "Mine SD", obligation_type_id: type.id, primary_assignee_id: member.user.id, someday: true, open_note: "n"})
      {:ok, _other} = Obligations.create_obligation(m, %{title: "Other SD", obligation_type_id: type.id, someday: true, open_note: "n"})

      page = Obligations.list_obligations_page(member, status: :my_live, date_scope: :someday, sort: :recent, limit: :all)
      assert Enum.map(page.rows, & &1.id) == [mine.id]
    end

    test "recent sort still keyset-pages newest-first", %{manager: m, someday: [x, y, z]} do
      p1 = Obligations.list_obligations_page(m, status: :live, date_scope: :someday, sort: :recent, limit: 2)
      assert Enum.map(p1.rows, & &1.id) == [z.id, y.id]
      p2 = Obligations.list_obligations_page(m, status: :live, date_scope: :someday, sort: :recent, limit: 2, cursor: p1.cursor)
      assert Enum.map(p2.rows, & &1.id) == [x.id]
      assert p2.end?
    end
  end
```

Run: `mix test test/argus/obligations_test.exs -k "date_scope"`
Expected: FAIL (`:date_scope` not supported; `status: :live` currently excludes dateless via `apply_page_status`).

- [ ] **Step 2: Implement the query changes**

In `lib/argus/obligations.ex`:

Revert `@status_filters`:

```elixir
  @status_filters ~w(my_live my_completed my_skipped my_all live completed skipped all)a
```

Remove the `apply_status_filter(:someday/:my_someday)` clause (delete it). Revert `scope_to_assignee/3`'s guard to `when status in [:my_live, :my_completed, :my_skipped, :my_all]` (drop `:my_someday`).

Delete `apply_page_status/2` entirely. In `list_obligations_page/2`, change the pipeline line `|> apply_page_status(status)` to `|> apply_status_filter(status)`, and insert a date-scope step right after it:

```elixir
      |> apply_status_filter(status)
      |> apply_date_scope(Keyword.get(opts, :date_scope, :all_dates))
```

Add the helper near `apply_status_filter/2`:

```elixir
  defp apply_date_scope(query, :dated), do: where(query, [o], not is_nil(o.due_by))
  defp apply_date_scope(query, :someday), do: where(query, [o], is_nil(o.due_by))
  defp apply_date_scope(query, _all_dates), do: query
```

- [ ] **Step 3: Run query tests (GREEN)**

Run: `mix test test/argus/obligations_test.exs`
Expected: PASS.

- [ ] **Step 4: Update IndexHelpers tests to the new vocabulary (RED)**

In `test/argus_web/live/index_helpers_test.exs`, replace the someday-lifecycle test(s) (the `"someday lifecycle: …"` test and the `describe "load_page urgency on live"` block's references, plus any `sorts(:someday)`/`status_atom(_, :someday)` assertions) with date_filter-based ones:

```elixir
  test "date_filter vocabulary + lifecycle-aware sorts" do
    assert {"someday", "Someday"} = List.keyfind(Index.date_filters(), "someday", 0)
    assert Index.parse_date_filter("all_dates") == :all_dates
    assert Index.parse_date_filter("bogus") == :dated

    # urgency only on live × dated; recent only on someday; due on dated/all; title always
    assert {"urgency", _} = List.keyfind(Index.sorts(:live, :dated), "urgency", 0)
    refute List.keyfind(Index.sorts(:live, :all_dates), "urgency", 0)
    refute List.keyfind(Index.sorts(:completed, :dated), "urgency", 0)
    assert {"recent", _} = List.keyfind(Index.sorts(:completed, :someday), "recent", 0)
    refute List.keyfind(Index.sorts(:live, :dated), "recent", 0)
    assert {"due_asc", _} = List.keyfind(Index.sorts(:completed, :all_dates), "due_asc", 0)
    refute List.keyfind(Index.sorts(:live, :someday), "due_asc", 0)

    assert Index.effective_sort(:urgency, :live, :dated) == :urgency
    assert Index.effective_sort(:urgency, :live, :all_dates) == :due_asc
    assert Index.effective_sort(:due_asc, :live, :someday) == :recent
    assert Index.effective_sort(:recent, :completed, :dated) == :due_asc
  end
```

Keep the existing non-someday `load_page` test but update its call to the new arity — change `Index.load_page(manager, today, false, :live, "", :due_asc, nil)` to `Index.load_page(manager, today, false, :live, :dated, "", :due_asc, nil)`. Also update the urgency `describe` block's `load_page(..., :live, "", :urgency, nil)` calls to `load_page(..., :live, :dated, "", :urgency, nil)`.

Run: `mix test test/argus_web/live/index_helpers_test.exs`
Expected: FAIL (`date_filters/0`, `sorts/2`, `effective_sort/3`, `load_page/8` undefined).

- [ ] **Step 5: Implement IndexHelpers**

In `lib/argus_web/live/obligation_live/index_helpers.ex`:

Revert `@lifecycles` and remove the someday-lifecycle clauses:

```elixir
  @lifecycles ~w(live completed skipped all)a
```

Delete `parse_lifecycle("someday")`, `lifecycle_label(:someday)`, `status_atom(true, :someday)`, and the `empty_message(mine?, :someday)` clause.

Add the date-filter vocabulary (near `lifecycles/0`):

```elixir
  @doc "Due-date filter options as {value, label} pairs."
  def date_filters,
    do: [{"dated", "Has due date"}, {"someday", "Someday"}, {"all_dates", "All dates"}]

  def parse_date_filter("someday"), do: :someday
  def parse_date_filter("all_dates"), do: :all_dates
  def parse_date_filter(_), do: :dated
```

Replace `sorts/1` + `default_sort/1` + `effective_sort/2` with the `(lifecycle, date_filter)` versions:

```elixir
  def sorts(lifecycle, date_filter) do
    base =
      case date_filter do
        :someday -> [{"recent", "Recently added"}]
        _ -> [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}]
      end

    urgency =
      if lifecycle == :live and date_filter == :dated, do: [{"urgency", "Most urgent"}], else: []

    base ++ urgency ++ [{"title", "Title A–Z"}]
  end

  def effective_sort(sort, lifecycle, date_filter) do
    allowed = Enum.map(sorts(lifecycle, date_filter), fn {v, _} -> parse_sort(v) end)
    if sort in allowed, do: sort, else: default_sort(date_filter)
  end

  defp default_sort(:someday), do: :recent
  defp default_sort(_), do: :due_asc
```

(Keep `parse_sort/1` unchanged — it still maps `recent`/`urgency`/`due_*`/`title`.)

Replace `empty_message/2` with `empty_message/3`:

```elixir
  def empty_message(mine?, _lifecycle, :someday) do
    who = if mine?, do: " assigned to you", else: ""
    "No someday duties#{who}."
  end

  def empty_message(mine?, lifecycle, _date_filter) do
    who = if mine?, do: " assigned to you", else: ""

    case lifecycle do
      :live -> "No live duties#{who}."
      :completed -> "No completed duties#{who}."
      :skipped -> "No skipped duties#{who}."
      :all -> "No duties#{who}."
    end
  end
```

Replace `load_page/7` with `load_page/8` + a `/7` shim, and thread `date_filter` → `date_scope`:

```elixir
  # Transitional shim: callers not yet passing date_filter get the default (:dated).
  def load_page(scope, today, mine?, lifecycle, query, sort, cursor),
    do: load_page(scope, today, mine?, lifecycle, :dated, query, sort, cursor)

  def load_page(scope, today, mine?, lifecycle, date_filter, query, sort, cursor) do
    status = status_atom(mine?, lifecycle)
    eff = effective_sort(sort, lifecycle, date_filter)
    do_load_page(scope, today, status, date_filter, query, eff, cursor)
  end

  defp do_load_page(scope, today, status, date_filter, query, sort, cursor)
       when sort != :urgency do
    page =
      Obligations.list_obligations_page(scope,
        status: status,
        date_scope: date_filter,
        query: query,
        sort: sort,
        cursor: cursor,
        limit: @page_size
      )

    %{rows: build_rows(page.rows, today), cursor: page.cursor, end?: page.end?}
  end

  # urgency only reaches here for live × dated (effective_sort guarantees it).
  defp do_load_page(scope, today, status, :dated, query, :urgency, cursor) do
    window_end = Date.add(today, @urgency_window_days)

    case decode_urgency_cursor(cursor) do
      {:window, offset} -> serve_window(scope, today, status, window_end, query, offset)
      {:tail, inner} -> serve_tail(scope, today, status, window_end, query, inner)
    end
  end
```

Update `serve_window/6` and `serve_tail/6` to pass `date_scope: :dated` to their `list_obligations_page` calls (the window/tail are dated by definition):

```elixir
  defp serve_window(scope, today, status, window_end, query, offset) do
    ranked =
      scope
      |> Obligations.list_obligations_page(
        status: status,
        date_scope: :dated,
        query: query,
        sort: :due_asc,
        due_before: window_end,
        limit: :all
      )
      |> Map.fetch!(:rows)
      |> Enum.sort_by(fn %Obligation{} = o ->
        {@urgency_rank[Urgency.classify(o.obligation_type, o.due_by, today)], Date.to_iso8601(o.due_by)}
      end)

    page = ranked |> Enum.slice(offset, @page_size) |> build_rows(today)
    next_offset = offset + @page_size

    if next_offset < length(ranked) do
      %{rows: page, cursor: encode_urgency_cursor({:window, next_offset}), end?: false}
    else
      %{rows: page, cursor: encode_urgency_cursor({:tail, nil}), end?: false}
    end
  end

  defp serve_tail(scope, today, status, window_end, query, inner_cursor) do
    page =
      Obligations.list_obligations_page(scope,
        status: status,
        date_scope: :dated,
        query: query,
        sort: :due_asc,
        due_after: window_end,
        cursor: inner_cursor
      )

    cursor = if page.end?, do: nil, else: encode_urgency_cursor({:tail, page.cursor})
    %{rows: build_rows(page.rows, today), cursor: cursor, end?: page.end?}
  end
```

(The `do_load_page` arg order changed from `(scope, today, status, lifecycle, query, sort, cursor)` to `(scope, today, status, date_filter, query, sort, cursor)`; `serve_window`/`serve_tail` arg order is shown above — apply consistently.)

- [ ] **Step 6: Remove the now-invalid someday-lifecycle dashboard tests**

The dashboard tests that switch `lifecycle: "someday"` no longer apply (Someday isn't a lifecycle). In `test/argus_web/live/dashboard_live_test.exs` delete the test `"Someday tab lists dateless duties without urgency/due chrome"`. In `test/argus_web/live/mobile_live_test.exs` delete the test `"mobile dateless-card guards for Someday lifecycle"` (the one switching to the `someday` lifecycle). The dateless-card rendering is re-covered via the new Due-date dropdown tests in Tasks 3–4.

- [ ] **Step 7: Run the full suite (GREEN)**

Run: `mix precommit`
Expected: PASS. (Dashboards still call `load_page/7` shim → `:dated` default, so the Live view is unchanged; Someday is simply absent from the lifecycle dropdown until Tasks 3–4 add the Due-date control.)

- [ ] **Step 8: Commit**

```bash
git add lib/argus/obligations.ex lib/argus_web/live/obligation_live/index_helpers.ex test/argus/obligations_test.exs test/argus_web/live/index_helpers_test.exs test/argus_web/live/dashboard_live_test.exs test/argus_web/live/mobile_live_test.exs
git commit -m "refactor: Someday becomes a date_scope filter, not a lifecycle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Persist `date_filter` — `ArgusWeb.DashboardFilter`

**Files:**
- Modify: `lib/argus_web/dashboard_filter.ex`
- Test: `test/argus_web/dashboard_filter_test.exs`

**Interfaces:**
- Produces: the per-entity entry gains `"date_filter"`; `assign_filters/2` assigns `:date_filter` (default `:dated`, bogus → `:dated`); the `store-dashboard-filter` push payload carries `date_filter`.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/dashboard_filter_test.exs`:

```elixir
    test "restores a saved date_filter and defaults to dated" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "completed", "query" => "", "sort" => "recent", "date_filter" => "someday"}
        }
      }

      assert %{date_filter: :someday} = DashboardFilter.load(session, scope(:manager, "acme"))
      assert %{date_filter: :dated} = DashboardFilter.load(%{}, scope(:manager, "beta"))
    end

    test "rejects a bogus date_filter" do
      session = %{"dashboard_filters" => %{"acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "due_asc", "date_filter" => "nope"}}}
      assert %{date_filter: :dated} = DashboardFilter.load(session, scope(:manager, "acme"))
    end
```

Also update the existing `merge_session/3` "stores normalized filter values" test to expect a `"date_filter" => "dated"` key in the output map (add it to both the input and the expected map).

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/dashboard_filter_test.exs`
Expected: FAIL (missing `:date_filter`).

- [ ] **Step 3: Implement**

In `lib/argus_web/dashboard_filter.ex`:

Revert the lifecycle whitelist and add a date_filter whitelist:

```elixir
  @lifecycles ~w(live completed skipped all)
  @date_filters ~w(dated someday all_dates)
```

Assign `:date_filter` in `assign_filters/2`:

```elixir
    |> Phoenix.Component.assign(:sort, filters.sort)
    |> Phoenix.Component.assign(:date_filter, filters.date_filter)
```

Add `"date_filter"` to `current_entry/1` and `session_entry/1`:

```elixir
  # current_entry/1:
      "sort" => Atom.to_string(socket.assigns.sort),
      "date_filter" => Atom.to_string(socket.assigns.date_filter)

  # session_entry/1:
      "sort" => param_sort(params["sort"]),
      "date_filter" => param_date_filter(params["date_filter"])
```

Add `date_filter` to `merge_saved/2` and `defaults/1`:

```elixir
  # merge_saved/2 map:
      sort: parse_sort(Map.get(saved, "sort")),
      date_filter: parse_date_filter(Map.get(saved, "date_filter"))

  # defaults/1 map:
      sort: :due_asc,
      date_filter: :dated
```

Add the parsers near `param_sort`/`parse_sort`:

```elixir
  defp param_date_filter(df) when df in @date_filters, do: df
  defp param_date_filter(_), do: "dated"

  defp parse_date_filter("someday"), do: :someday
  defp parse_date_filter("all_dates"), do: :all_dates
  defp parse_date_filter(_), do: :dated
```

Add `date_filter` to the `persist/1` push payload:

```elixir
      sort: entry["sort"],
      date_filter: entry["date_filter"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/dashboard_filter_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/dashboard_filter.ex test/argus_web/dashboard_filter_test.exs
git commit -m "feat: persist the dashboard date_filter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Desktop dashboard — "Due date" dropdown

**Files:**
- Modify: `lib/argus_web/live/dashboard_live/index.ex`
- Test: `test/argus_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `IndexHelpers.date_filters/0`, `parse_date_filter/1`, `sorts/2`, `load_page/8`, `empty_message/3`; `DashboardFilter` now assigns `:date_filter`.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/dashboard_live_test.exs`:

```elixir
  test "Due date filter shows Someday duties within a lifecycle", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(manager.user |> then(fn u -> conn |> log_in_user(u) end) && conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, dated} = Obligations.create_obligation(manager, %{title: "Has a deadline", obligation_type_id: type.id, due_by: ~D[2026-07-01], open_note: "n"})
    {:ok, _sd} = Obligations.create_obligation(manager, %{title: "Tidy the archive", obligation_type_id: type.id, someday: true, open_note: "n"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    # Default (Has due date): dated shows, someday hidden.
    html = view |> element("#obligations-list") |> render()
    assert html =~ "Has a deadline"
    refute html =~ "Tidy the archive"

    # Switch Due date → Someday: someday shows, dated hidden, no "due " chrome.
    view |> form("#obligation-date-filter", %{date_filter: "someday"}) |> render_change()
    html = view |> element("#obligations-list") |> render()
    assert html =~ "Tidy the archive"
    refute html =~ "Has a deadline"
    refute html =~ "due "
    refute has_element?(view, "#obligation-sort option[value='urgency']")
    assert has_element?(view, "#obligation-sort option[value='recent']")
  end
```

(If `log_in_user` is already applied by a setup, simplify the conn line to `conn = log_in_user(conn, manager.user)`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/dashboard_live_test.exs -k "Due date filter"`
Expected: FAIL (no `#obligation-date-filter`).

- [ ] **Step 3: Implement**

In `lib/argus_web/live/dashboard_live/index.ex`:

Add the Due-date `<select>` right after the `#obligation-status-filter` form:

```heex
            <form id="obligation-date-filter-form" phx-change="set_date_filter">
              <select id="obligation-date-filter" name="date_filter" class="select">
                <option
                  :for={{value, label} <- Index.date_filters()}
                  value={value}
                  selected={@date_filter == Index.parse_date_filter(value)}
                >
                  {label}
                </option>
              </select>
            </form>
```

Change the sort `<select>`'s options source from `Index.sorts(@lifecycle)` to `Index.sorts(@lifecycle, @date_filter)`.

Change the empty-state call from `Index.empty_message(@mine?, @lifecycle)` to `Index.empty_message(@mine?, @lifecycle, @date_filter)`.

Add the handler (next to `set_sort`):

```elixir
  def handle_event("set_date_filter", %{"date_filter" => df}, socket) do
    {:noreply,
     socket
     |> assign(:date_filter, Index.parse_date_filter(df))
     |> load_first_page()
     |> DashboardFilter.persist()}
  end
```

Thread `@date_filter` into both `load_page` calls (in `load_more` and `load_first_page`), switching to the 8-arg form:

```elixir
  # load_more:
      Index.load_page(scope, today, mine?, lifecycle, date_filter, query, sort, cursor)
  # load_first_page:
      Index.load_page(scope, today, mine?, lifecycle, date_filter, query, sort, nil)
```

In both, destructure `date_filter` from `socket.assigns` alongside the others (add `date_filter:` to the `%{...} = socket.assigns` patterns).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/live/dashboard_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/dashboard_live/index.ex test/argus_web/live/dashboard_live_test.exs
git commit -m "feat: desktop Due-date filter (dated/someday/all)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Mobile dashboard — "Due date" dropdown + remove the `load_page/7` shim

**Files:**
- Modify: `lib/argus_web/live/mobile_live/dashboard.ex`
- Modify: `lib/argus_web/live/obligation_live/index_helpers.ex` (remove the shim)
- Test: `test/argus_web/live/mobile_live_test.exs`

**Interfaces:**
- Consumes: same IndexHelpers functions as Task 3. After this task, all callers use `load_page/8` and the `/7` shim is removed.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/mobile_live_test.exs`:

```elixir
  test "mobile Due date filter shows Someday duties", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, _dated} = Argus.Obligations.create_obligation(manager, %{title: "Has a deadline", obligation_type_id: type.id, due_by: ~D[2026-07-01], open_note: "n"})
    {:ok, _sd} = Argus.Obligations.create_obligation(manager, %{title: "Tidy the archive", obligation_type_id: type.id, someday: true, open_note: "n"})

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")
    assert view |> element("#mobile-obligations") |> render() =~ "Has a deadline"

    view |> form("#m-obligation-date-filter-form", %{date_filter: "someday"}) |> render_change()
    html = view |> element("#mobile-obligations") |> render()
    assert html =~ "Tidy the archive"
    refute html =~ "Has a deadline"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/mobile_live_test.exs -k "Due date filter"`
Expected: FAIL (no `#m-obligation-date-filter`).

- [ ] **Step 3: Implement (mobile)**

In `lib/argus_web/live/mobile_live/dashboard.ex`, add the Due-date `<select>` into the header control row (next to the status/sort selects):

```heex
          <form id="m-obligation-date-filter-form" phx-change="set_date_filter">
            <select id="m-obligation-date-filter" name="date_filter" class="select">
              <option
                :for={{value, label} <- Index.date_filters()}
                value={value}
                selected={@date_filter == Index.parse_date_filter(value)}
              >
                {label}
              </option>
            </select>
          </form>
```

Change the sort `<select>` source to `Index.sorts(@lifecycle, @date_filter)`; change the empty message to `Index.empty_message(@mine?, @lifecycle, @date_filter)`. Add the `set_date_filter` handler (identical body to Task 3's). Thread `date_filter` into both `load_page` calls (8-arg form) and into the `%{...} = socket.assigns` destructures in `load_more`/`load_first_page`.

- [ ] **Step 4: Remove the transitional shim**

Now that both dashboards call `load_page/8`, delete the `load_page/7` shim clause from `lib/argus_web/live/obligation_live/index_helpers.ex` (the two-line clause that delegates with `:dated`).

- [ ] **Step 5: Run the full gate**

Run: `mix precommit`
Expected: PASS (compile `--warnings-as-errors` confirms no remaining `load_page/7` caller; full suite green).

- [ ] **Step 6: Commit**

```bash
git add lib/argus_web/live/mobile_live/dashboard.ex lib/argus_web/live/obligation_live/index_helpers.ex test/argus_web/live/mobile_live_test.exs
git commit -m "feat: mobile Due-date filter; drop the load_page/7 shim

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- `date_scope` query filter (dated/someday/all_dates) composing with lifecycle, `:someday` status retired → Task 1.
- Sort availability `(lifecycle × date_filter)`, `effective_sort/3`, `date_filters`/`parse_date_filter`, `empty_message/3`, urgency window only for live×dated → Task 1.
- NULLS-LAST keyset + `:recent` kept → Task 1 (unchanged code paths).
- `date_filter` persistence (default dated) → Task 2.
- Desktop + mobile "Due date" dropdown, sort options react, default Live×dated, Completed×Someday view, persistence → Tasks 3, 4.
- Lifecycle dropdown reverts to Live·Completed·Skipped·All → Task 1 (`@lifecycles`) + auto via `lifecycles/0`.

**Placeholder scan:** every code step is complete. The one "if log_in_user is in a setup, simplify" note (Task 3 Step 1) names the exact simplification.

**Type consistency:** `date_filter` atoms (`:dated`/`:someday`/`:all_dates`) and string values (`"dated"`/`"someday"`/`"all_dates"`) are used consistently across Tasks 1–4; `load_page/8` signature `(scope, today, mine?, lifecycle, date_filter, query, sort, cursor)` is defined in Task 1 and consumed identically in Tasks 3–4; `sorts/2` and `effective_sort/3` defined in Task 1 are consumed in Tasks 3–4; the `load_page/7` shim is added in Task 1 and removed in Task 4 once both callers move to `/8`.
