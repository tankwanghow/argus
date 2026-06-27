# Dashboard Sorting + Infinite Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-controllable sorting and DB-paginated infinite scroll to the desktop and mobile dashboards.

**Architecture:** A single SQL keyset-pagination path (`Obligations.list_obligations_page/2`) handles filtering, sorting, and paging for every lifecycle. The one exception is "Most urgent + Live", which loads a 1-year `due_by` window into memory, urgency-ranks it, slices it for rendering, and continues into a `>1yr` SQL keyset tail. The lists become LiveView streams fed by a `phx-viewport-bottom` sentinel. The chosen sort persists per-entity alongside the existing dashboard filters.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8.5 / LiveView 1.2.1 / Ecto 3.13 / PostgreSQL / Jason.

**Spec:** `docs/superpowers/specs/2026-06-23-dashboard-sort-infinite-scroll-design.md`.

## Global Constraints

- Contexts own domain logic; LiveViews call `Tugas.Obligations`, never `Repo` directly.
- Unauthorized context calls return `:not_authorise` (not relevant to read paths here, but the convention stands).
- LiveView lists use **streams** (`phx-update="stream"`), never `:for` over a plain assign.
- `due_by` is `NOT NULL` on `Obligation`; no null-ordering edge cases.
- Sort preset values are exactly `due_asc | due_desc | title | urgency`. Default `due_asc`.
- Page size is `25`, defined once as `@page_size`.
- Urgency window is `365` days, defined once as `@urgency_window_days`.
- Run `mix precommit` before declaring the feature done.
- Every commit message ends with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## File Structure

- Create: `lib/tugas/obligations/pagination.ex` — keyset cursor encode/decode (idempotent).
- Modify: `lib/tugas/obligations.ex` — add `list_obligations_page/2` (SQL filter + sort + keyset paging; `due_before`/`due_after`/`limit: :all` options). Leaves the existing `list_obligations/2` intact for its other callers.
- Create: `priv/repo/migrations/<ts>_add_obligation_sort_indexes.exs` — keyset support indexes.
- Modify: `lib/tugas_web/dashboard_filter.ex` — add `sort` to the persisted entry.
- Modify: `lib/tugas_web/live/obligation_live/index_helpers.ex` — `sorts/1`, `parse_sort/1`, `effective_sort/2`, `load_page/7`, `build_rows/2`, urgency window+tail; remove the lifecycle-keyed `sort_rows/2`.
- Modify: `lib/tugas_web/live/dashboard_live/index.ex` — streams, sort `<select>`, `load_more`, reset-on-change.
- Modify: `lib/tugas_web/live/mobile_live/dashboard.ex` — same as desktop, mobile markup.
- Modify: `lib/tugas_web/live/mobile_live/components.ex` — `obligation_card` gains a required `id` attr.
- Tests: `test/tugas/obligations/pagination_test.exs` (new), `test/tugas/obligations_test.exs`, `test/tugas_web/dashboard_filter_test.exs`, `test/tugas_web/live/index_helpers_test.exs` (new), `test/tugas_web/live/dashboard_live_test.exs`, `test/tugas_web/live/mobile_live_test.exs`.

---

### Task 1: Keyset cursor codec — `Tugas.Obligations.Pagination`

**Files:**
- Create: `lib/tugas/obligations/pagination.ex`
- Test: `test/tugas/obligations/pagination_test.exs`

**Interfaces:**
- Produces:
  - `Pagination.encode(%{key: String.t(), id: String.t()}) :: String.t()` and `encode(nil) :: nil`
  - `Pagination.decode(String.t() | map | nil) :: %{key: String.t(), id: String.t()} | nil` — idempotent on an already-decoded atom-keyed map; returns `nil` for `nil`, `""`, or any malformed input.

- [ ] **Step 1: Write the failing test**

```elixir
# test/tugas/obligations/pagination_test.exs
defmodule Tugas.Obligations.PaginationTest do
  use ExUnit.Case, async: true

  alias Tugas.Obligations.Pagination

  test "round-trips a key/id cursor" do
    cursor = %{key: "2026-06-15", id: "abc-123"}
    assert cursor |> Pagination.encode() |> Pagination.decode() == cursor
  end

  test "encode(nil) and decode(nil) are nil" do
    assert Pagination.encode(nil) == nil
    assert Pagination.decode(nil) == nil
  end

  test "decode is idempotent on an already-decoded map" do
    cursor = %{key: "x", id: "y"}
    assert Pagination.decode(cursor) == cursor
  end

  test "decode returns nil for garbage" do
    assert Pagination.decode("") == nil
    assert Pagination.decode("not-base64-$$$") == nil
    assert Pagination.decode(Base.url_encode64("not json", padding: false)) == nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/obligations/pagination_test.exs`
Expected: FAIL with `Tugas.Obligations.Pagination` undefined.

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/tugas/obligations/pagination.ex
defmodule Tugas.Obligations.Pagination do
  @moduledoc false

  def encode(nil), do: nil

  def encode(%{key: key, id: id}) do
    %{"k" => key, "id" => id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def decode(nil), do: nil
  def decode(""), do: nil
  def decode(%{key: _, id: _} = cursor), do: cursor

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"k" => key, "id" => id}} <- Jason.decode(json) do
      %{key: key, id: id}
    else
      _ -> nil
    end
  end

  def decode(_), do: nil
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas/obligations/pagination_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/tugas/obligations/pagination.ex test/tugas/obligations/pagination_test.exs
git commit -m "feat: add keyset cursor codec for obligation pagination

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: SQL paginated query — `Obligations.list_obligations_page/2`

**Files:**
- Modify: `lib/tugas/obligations.ex`
- Test: `test/tugas/obligations_test.exs`

**Interfaces:**
- Consumes: `Tugas.Obligations.Pagination.decode/1`, `Pagination.encode/1` (Task 1).
- Produces:
  `list_obligations_page(%Scope{}, opts) :: %{rows: [%Obligation{}], cursor: String.t() | nil, end?: boolean}`
  where `opts` may include `:status` (default `:live`, validated against `@status_filters`), `:query`, `:sort` (`:due_asc | :due_desc | :title | :urgency`; `:urgency` is normalized to `:due_asc` here — urgency ranking happens in IndexHelpers), `:cursor` (encoded string or decoded map), `:limit` (default `@page_size`, or `:all` for no paging), `:due_before` (`%Date{}` → `due_by <= date`), `:due_after` (`%Date{}` → `due_by > date`). Rows preload `:obligation_type` and `:primary_assignee`.

**Notes:** `lib/tugas/obligations.ex` already `import Ecto.Query` and defines `@status_filters`, `scope_to_assignee/3`, `apply_status_filter/2`, and `live/1`. Reuse them. Add `alias Tugas.Obligations.Pagination` near the other aliases.

- [ ] **Step 1: Write the failing test**

Add to `test/tugas/obligations_test.exs` inside a new `describe`:

```elixir
  describe "list_obligations_page/2" do
    setup do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      mk = fn title, due ->
        {:ok, o} =
          Obligations.create_obligation(manager, %{
            title: title,
            obligation_type_id: type.id,
            due_by: due,
            open_note: "n"
          })

        o
      end

      a = mk.("Alpha", ~D[2026-03-01])
      b = mk.("bravo", ~D[2026-01-01])
      c = mk.("Charlie", ~D[2026-02-01])
      %{manager: manager, a: a, b: b, c: c}
    end

    test "sorts due_asc with stable keyset paging", %{manager: m, a: a, b: b, c: c} do
      page1 = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, limit: 2)
      assert Enum.map(page1.rows, & &1.id) == [b.id, c.id]
      refute page1.end?

      page2 = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, limit: 2, cursor: page1.cursor)
      assert Enum.map(page2.rows, & &1.id) == [a.id]
      assert page2.end?
    end

    test "sorts due_desc and title", %{manager: m, a: a, b: b, c: c} do
      desc = Obligations.list_obligations_page(m, status: :live, sort: :due_desc, limit: 10)
      assert Enum.map(desc.rows, & &1.id) == [a.id, c.id, b.id]

      title = Obligations.list_obligations_page(m, status: :live, sort: :title, limit: 10)
      assert Enum.map(title.rows, & &1.id) == [a.id, b.id, c.id]
    end

    test "search filters by title in SQL", %{manager: m, b: b} do
      page = Obligations.list_obligations_page(m, status: :live, query: "brav")
      assert Enum.map(page.rows, & &1.id) == [b.id]
    end

    test "due_before and due_after bound the window", %{manager: m, b: b, c: c, a: a} do
      before = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, due_before: ~D[2026-02-15], limit: 10)
      assert Enum.map(before.rows, & &1.id) == [b.id, c.id]

      after_ = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, due_after: ~D[2026-02-15], limit: 10)
      assert Enum.map(after_.rows, & &1.id) == [a.id]
    end

    test "limit: :all returns everything with end? true", %{manager: m} do
      page = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, limit: :all)
      assert length(page.rows) == 3
      assert page.end?
      assert page.cursor == nil
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/obligations_test.exs -k "list_obligations_page"` (or run the file).
Expected: FAIL with `list_obligations_page/2` undefined.

- [ ] **Step 3: Write minimal implementation**

Add `alias Tugas.Obligations.Pagination` with the other aliases, then add the function and its private helpers (place near `list_obligations/2`):

```elixir
  @page_size 25

  def list_obligations_page(%Scope{entity: entity, user: user} = scope, opts \\ []) do
    status = Keyword.get(opts, :status, :live)
    sort = normalize_page_sort(Keyword.get(opts, :sort, :due_asc))
    cursor = Pagination.decode(Keyword.get(opts, :cursor))
    limit = Keyword.get(opts, :limit, @page_size)

    unless status in @status_filters do
      raise ArgumentError, "invalid status filter #{inspect(status)}"
    end

    query =
      Obligation
      |> join(:left, [o], t in assoc(o, :obligation_type), as: :type)
      |> join(:left, [o], a in assoc(o, :primary_assignee), as: :assignee)
      |> where([o], o.entity_id == ^entity.id)
      |> scope_to_assignee(status, user)
      |> apply_status_filter(status)
      |> apply_due_bound(:before, Keyword.get(opts, :due_before))
      |> apply_due_bound(:after, Keyword.get(opts, :due_after))
      |> apply_page_search(Keyword.get(opts, :query))
      |> apply_page_order(sort)
      |> apply_page_cursor(sort, cursor)
      |> preload([:obligation_type, :primary_assignee])

    query
    |> maybe_limit(limit)
    |> Repo.all()
    |> paginate(sort, limit)
  end

  defp normalize_page_sort(sort) when sort in [:due_asc, :due_desc, :title], do: sort
  defp normalize_page_sort(_), do: :due_asc

  defp apply_due_bound(query, _which, nil), do: query
  defp apply_due_bound(query, :before, %Date{} = d), do: where(query, [o], o.due_by <= ^d)
  defp apply_due_bound(query, :after, %Date{} = d), do: where(query, [o], o.due_by > ^d)

  defp apply_page_search(query, q) when q in [nil, ""], do: query

  defp apply_page_search(query, q) do
    like = "%#{escape_like(q)}%"
    unassigned? = String.contains?("unassigned", String.downcase(q))

    from [o, type: t, assignee: a] in query,
      where:
        ilike(o.title, ^like) or ilike(t.name, ^like) or ilike(a.email, ^like) or
          (^unassigned? and is_nil(o.primary_assignee_id))
  end

  defp escape_like(q), do: String.replace(q, ["\\", "%", "_"], &("\\" <> &1))

  defp apply_page_order(query, :due_asc), do: order_by(query, [o], asc: o.due_by, asc: o.id)
  defp apply_page_order(query, :due_desc), do: order_by(query, [o], desc: o.due_by, asc: o.id)

  defp apply_page_order(query, :title),
    do: order_by(query, [o], asc: fragment("lower(?)", o.title), asc: o.id)

  defp apply_page_cursor(query, _sort, nil), do: query

  defp apply_page_cursor(query, :due_asc, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} -> where(query, [o], o.due_by > ^d or (o.due_by == ^d and o.id > ^id))
      _ -> query
    end
  end

  defp apply_page_cursor(query, :due_desc, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} -> where(query, [o], o.due_by < ^d or (o.due_by == ^d and o.id > ^id))
      _ -> query
    end
  end

  defp apply_page_cursor(query, :title, %{key: k, id: id}) do
    where(
      query,
      [o],
      fragment("lower(?)", o.title) > ^k or
        (fragment("lower(?)", o.title) == ^k and o.id > ^id)
    )
  end

  defp maybe_limit(query, :all), do: query
  defp maybe_limit(query, limit), do: limit(query, ^(limit + 1))

  defp paginate(rows, _sort, :all), do: %{rows: rows, cursor: nil, end?: true}

  defp paginate(rows, sort, limit) do
    {page, rest} = Enum.split(rows, limit)
    has_more = rest != []

    cursor =
      if has_more do
        last = List.last(page)
        Pagination.encode(%{key: cursor_key(sort, last), id: last.id})
      end

    %{rows: page, cursor: cursor, end?: not has_more}
  end

  defp cursor_key(:title, %Obligation{title: t}), do: String.downcase(t)
  defp cursor_key(_sort, %Obligation{due_by: d}), do: Date.to_iso8601(d)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas/obligations_test.exs`
Expected: PASS (new describe + existing tests).

- [ ] **Step 5: Commit**

```bash
git add lib/tugas/obligations.ex test/tugas/obligations_test.exs
git commit -m "feat: add SQL keyset-paginated list_obligations_page

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Migration — keyset support indexes

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_obligation_sort_indexes.exs`

**Interfaces:** none (schema-only). Generate the timestamped file with `mix ecto.gen.migration add_obligation_sort_indexes` so the prefix is correct.

- [ ] **Step 1: Generate the migration file**

Run: `mix ecto.gen.migration add_obligation_sort_indexes`
Expected: prints the created path under `priv/repo/migrations/`.

- [ ] **Step 2: Write the migration body**

Replace the generated file's contents:

```elixir
defmodule Tugas.Repo.Migrations.AddObligationSortIndexes do
  use Ecto.Migration

  def change do
    create index(:obligations, [:entity_id, :due_by, :id])

    create index(:obligations, [:entity_id, :due_by, :id],
             name: :obligations_completed_due_idx,
             where: "completed_at IS NOT NULL"
           )

    create index(:obligations, [:entity_id, :due_by, :id],
             name: :obligations_skipped_due_idx,
             where: "closed_at IS NOT NULL"
           )
  end
end
```

- [ ] **Step 3: Run the migration and the suite**

Run: `mix ecto.migrate && mix test test/tugas/obligations_test.exs`
Expected: migration applies cleanly; tests PASS.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/*_add_obligation_sort_indexes.exs
git commit -m "feat: add indexes for obligation keyset pagination

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Persist the `sort` filter — `TugasWeb.DashboardFilter`

**Files:**
- Modify: `lib/tugas_web/dashboard_filter.ex`
- Test: `test/tugas_web/dashboard_filter_test.exs`

**Interfaces:**
- Produces: the per-entity entry gains `"sort"`; `load/2` result and `assign_filters/2` now include `sort: :due_asc | :due_desc | :title | :urgency` (default `:due_asc`). `session_entry/1` normalizes `"sort"` via `param_sort/1` (whitelist, default `"due_asc"`).

- [ ] **Step 1: Write the failing test**

Add to `test/tugas_web/dashboard_filter_test.exs`:

```elixir
    test "restores a saved sort and defaults to due_asc" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "title"}
        }
      }

      assert %{sort: :title} = DashboardFilter.load(session, scope(:manager, "acme"))
      assert %{sort: :due_asc} = DashboardFilter.load(%{}, scope(:manager, "acme"))
    end

    test "rejects a bogus sort value" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "bogus"}
        }
      }

      assert %{sort: :due_asc} = DashboardFilter.load(session, scope(:manager, "acme"))
    end
```

Also update the existing `merge_session/3` "stores normalized filter values" test to expect the `"sort"` key:

```elixir
      assert DashboardFilter.merge_session(%{}, "acme", %{
               "mine" => true,
               "lifecycle" => "completed",
               "query" => "tax",
               "sort" => "title"
             }) == %{
               "acme" => %{
                 "mine" => "true",
                 "lifecycle" => "completed",
                 "query" => "tax",
                 "sort" => "title"
               }
             }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/dashboard_filter_test.exs`
Expected: FAIL (missing `:sort`, and the merge_session map lacks `"sort"`).

- [ ] **Step 3: Write minimal implementation**

In `lib/tugas_web/dashboard_filter.ex`:

Add the sorts module attr near `@lifecycles`:

```elixir
  @sorts ~w(due_asc due_desc title urgency)
```

Assign `:sort` in `assign_filters/2`:

```elixir
    socket
    |> Phoenix.Component.assign(:mine?, filters.mine?)
    |> Phoenix.Component.assign(:lifecycle, filters.lifecycle)
    |> Phoenix.Component.assign(:query, filters.query)
    |> Phoenix.Component.assign(:sort, filters.sort)
```

Add `"sort"` to `current_entry/1`:

```elixir
  defp current_entry(socket) do
    session_entry(%{
      "mine" => if(socket.assigns.mine?, do: "true", else: "false"),
      "lifecycle" => Atom.to_string(socket.assigns.lifecycle),
      "query" => socket.assigns.query,
      "sort" => Atom.to_string(socket.assigns.sort)
    })
  end
```

Add `"sort"` to `session_entry/1`:

```elixir
  defp session_entry(params) do
    %{
      "mine" => param_mine(params["mine"]),
      "lifecycle" => param_lifecycle(params["lifecycle"]),
      "query" => param_query(params["query"]),
      "sort" => param_sort(params["sort"])
    }
  end
```

Add `sort` to `merge_saved/2` and `defaults/1`:

```elixir
  defp merge_saved(%{"mine" => mine, "lifecycle" => lifecycle, "query" => query} = saved, scope) do
    defaults = defaults(scope)

    %{
      mine?: parse_mine(mine, defaults.mine?),
      lifecycle: Index.parse_lifecycle(lifecycle),
      query: query || "",
      sort: parse_sort(Map.get(saved, "sort"))
    }
  end

  defp merge_saved(_, scope), do: defaults(scope)

  defp defaults(%Scope{} = scope) do
    %{
      mine?: Index.default_mine?(scope),
      lifecycle: :live,
      query: "",
      sort: :due_asc
    }
  end
```

Add the parsers near the other `param_*` helpers:

```elixir
  defp param_sort(sort) when sort in @sorts, do: sort
  defp param_sort(_), do: "due_asc"

  defp parse_sort("due_desc"), do: :due_desc
  defp parse_sort("title"), do: :title
  defp parse_sort("urgency"), do: :urgency
  defp parse_sort(_), do: :due_asc
```

Update the `push_event` payload in `persist/1` to include `sort`:

```elixir
    Phoenix.LiveView.push_event(socket, "store-dashboard-filter", %{
      entity_slug: slug,
      mine: entry["mine"],
      lifecycle: entry["lifecycle"],
      query: entry["query"],
      sort: entry["sort"]
    })
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/dashboard_filter_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/dashboard_filter.ex test/tugas_web/dashboard_filter_test.exs
git commit -m "feat: persist dashboard sort alongside the other filters

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: IndexHelpers — sort options + non-urgency `load_page/7`

**Files:**
- Modify: `lib/tugas_web/live/obligation_live/index_helpers.ex`
- Test: `test/tugas_web/live/index_helpers_test.exs` (new)

**Interfaces:**
- Consumes: `Obligations.list_obligations_page/2` (Task 2), `Obligations.event_summaries_for/1`.
- Produces:
  - `sorts(lifecycle) :: [{value :: String.t(), label :: String.t()}]` — four options for `:live`, three (no urgency) otherwise.
  - `parse_sort(String.t()) :: :due_asc | :due_desc | :title | :urgency` (default `:due_asc`).
  - `effective_sort(sort, lifecycle) :: sort` — `:urgency` stays only on `:live`, otherwise becomes `:due_asc`.
  - `load_page(scope, today, mine?, lifecycle, query, sort, cursor) :: %{rows: [row], cursor: String.t() | nil, end?: boolean}` where each `row` is the existing map (`obligation`, `cycle_status`, `urgency`, `tier`, `event_count`, `latest_event`). This task implements every case **except** `effective_sort == :urgency`, which Task 6 adds.

**Note:** remove the old `sort_rows/2` clauses and the `|> sort_rows(lifecycle)` call from `load_rows/5`. `load_rows/5` may stay (other callers) but must no longer reference `sort_rows/2`; if no caller remains after Tasks 7–8, delete it then. For now, repoint its tail to `build_rows/2` without sorting.

- [ ] **Step 1: Write the failing test**

```elixir
# test/tugas_web/live/index_helpers_test.exs
defmodule TugasWeb.ObligationLive.IndexHelpersTest do
  use Tugas.DataCase, async: true

  import Tugas.ObligationsFixtures

  alias TugasWeb.ObligationLive.IndexHelpers, as: Index
  alias Tugas.Obligations.Urgency

  test "sorts/1 includes urgency only for live" do
    assert {"urgency", _} = List.keyfind(Index.sorts(:live), "urgency", 0)
    refute List.keyfind(Index.sorts(:completed), "urgency", 0)
  end

  test "effective_sort keeps urgency on live, downgrades elsewhere" do
    assert Index.effective_sort(:urgency, :live) == :urgency
    assert Index.effective_sort(:urgency, :completed) == :due_asc
    assert Index.effective_sort(:title, :completed) == :title
  end

  test "parse_sort whitelists with due_asc default" do
    assert Index.parse_sort("title") == :title
    assert Index.parse_sort("bogus") == :due_asc
  end

  test "load_page returns paged rows for a non-urgency sort" do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    type = type_fixture(manager.entity)

    for {title, due} <- [{"a", ~D[2026-01-01]}, {"b", ~D[2026-02-01]}, {"c", ~D[2026-03-01]}] do
      {:ok, _} =
        Tugas.Obligations.create_obligation(manager, %{
          title: title,
          obligation_type_id: type.id,
          due_by: due,
          open_note: "n"
        })
    end

    today = Urgency.today_for(manager.entity.timezone)
    page = Index.load_page(manager, today, false, :live, "", :due_asc, nil)

    assert Enum.map(page.rows, & &1.obligation.title) == ["a", "b", "c"]
    assert page.end?
    assert Enum.all?(page.rows, &Map.has_key?(&1, :tier))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/index_helpers_test.exs`
Expected: FAIL (`sorts/1`, `effective_sort/2`, `parse_sort/1`, `load_page/7` undefined).

- [ ] **Step 3: Write minimal implementation**

In `lib/tugas_web/live/obligation_live/index_helpers.ex`:

Add the page size constant near `@urgency_rank`:

```elixir
  @page_size 25
```

Add the new public helpers (place after `lifecycles/0`):

```elixir
  @doc "Sort options for the dropdown; urgency is offered only on the live lifecycle."
  def sorts(:live),
    do: [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}, {"urgency", "Most urgent"}, {"title", "Title A–Z"}]

  def sorts(_lifecycle),
    do: [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}, {"title", "Title A–Z"}]

  def parse_sort("due_desc"), do: :due_desc
  def parse_sort("title"), do: :title
  def parse_sort("urgency"), do: :urgency
  def parse_sort(_), do: :due_asc

  def effective_sort(:urgency, :live), do: :urgency
  def effective_sort(:urgency, _lifecycle), do: :due_asc
  def effective_sort(sort, _lifecycle), do: sort
```

Add `load_page/7` and `build_rows/2` (place after `load_rows/5`):

```elixir
  def load_page(scope, today, mine?, lifecycle, query, sort, cursor) do
    status = status_atom(mine?, lifecycle)
    do_load_page(scope, today, status, lifecycle, query, effective_sort(sort, lifecycle), cursor)
  end

  # Non-urgency (and non-live urgency, already downgraded): straight SQL paging.
  defp do_load_page(scope, today, status, _lifecycle, query, sort, cursor) when sort != :urgency do
    page = Obligations.list_obligations_page(scope, status: status, query: query, sort: sort, cursor: cursor)
    %{rows: build_rows(page.rows, today), cursor: page.cursor, end?: page.end?}
  end

  defp build_rows(obligations, today) do
    summaries = Obligations.event_summaries_for(obligations)

    Enum.map(obligations, fn obligation ->
      %{event_count: event_count, latest_event: latest_event} =
        Map.fetch!(summaries, obligation.id)

      %{
        obligation: obligation,
        cycle_status: cycle_status(obligation),
        urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today),
        tier: Urgency.tier(obligation.obligation_type, obligation.due_by, today),
        event_count: event_count,
        latest_event: latest_event
      }
    end)
  end
```

Repoint `load_rows/5` to reuse `build_rows/2` and drop `sort_rows/2`:

```elixir
  def load_rows(scope, today, mine?, lifecycle, query) do
    status = status_atom(mine?, lifecycle)

    scope
    |> Obligations.list_obligations(status: status, query: query)
    |> build_rows(today)
  end
```

Delete the two `sort_rows/2` clauses (lines defining `sort_rows(rows, :live)` and `sort_rows(rows, _lifecycle)`).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/live/index_helpers_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/obligation_live/index_helpers.ex test/tugas_web/live/index_helpers_test.exs
git commit -m "feat: add sort options and SQL-paged load_page to IndexHelpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: IndexHelpers — urgency window + tail

**Files:**
- Modify: `lib/tugas_web/live/obligation_live/index_helpers.ex`
- Test: `test/tugas_web/live/index_helpers_test.exs`

**Interfaces:**
- Produces: `load_page/7` now also serves `effective_sort == :urgency` (live only). The first page loads the live `due_by <= today + 365d` window into memory, ranks by urgency then `due_by` (chronologically correct via ISO string), and slices `@page_size`. When the window is exhausted, paging continues into the `> today + 365d` SQL keyset tail (uniformly `:ok`). The returned `cursor` is an opaque urgency-tagged string consumed only by the next `load_page/7`.

**Note:** this fixes a latent bug in the deleted `sort_rows/2`, which ordered by the raw `%Date{}` struct — Erlang term order on `Date` maps compares day before month, so it was not chronological. The new code orders by `Date.to_iso8601/1`.

- [ ] **Step 1: Write the failing test**

Add to `test/tugas_web/live/index_helpers_test.exs`:

```elixir
  describe "load_page urgency on live" do
    setup do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      # reminder offset 30 days => due within 30d is due_soon, overdue is past.
      type = type_fixture(manager.entity, reminder_offsets: "30")
      today = ~D[2026-06-01]

      mk = fn title, due ->
        {:ok, o} =
          Tugas.Obligations.create_obligation(manager, %{
            title: title,
            obligation_type_id: type.id,
            due_by: due,
            open_note: "n"
          })

        o
      end

      overdue = mk.("overdue", ~D[2026-05-01])
      soon = mk.("soon", ~D[2026-06-10])
      ok = mk.("ok", ~D[2026-09-01])
      far = mk.("far", ~D[2027-12-01])
      %{manager: manager, today: today, overdue: overdue, soon: soon, ok: ok, far: far}
    end

    test "ranks overdue, then due_soon, then ok by due date; far tail loads last",
         %{manager: m, today: today, overdue: o, soon: s, ok: k, far: f} do
      p1 = TugasWeb.ObligationLive.IndexHelpers.load_page(m, today, false, :live, "", :urgency, nil)
      assert Enum.map(p1.rows, & &1.obligation.id) == [o.id, s.id, k.id]
      refute p1.end?

      p2 = TugasWeb.ObligationLive.IndexHelpers.load_page(m, today, false, :live, "", :urgency, p1.cursor)
      assert Enum.map(p2.rows, & &1.obligation.id) == [f.id]
      assert p2.end?
    end
  end
```

(Adjust `@page_size` assumptions: this set is 3 in-window + 1 tail, so the window fits one page and the tail follows. If `@page_size` is 25 the window page returns all 3 and hands to the tail with a `{:tail, nil}` cursor; the test above asserts exactly that handoff.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/index_helpers_test.exs`
Expected: FAIL (urgency case raises a `FunctionClauseError` in `do_load_page/7`, which currently only matches `sort != :urgency`).

- [ ] **Step 3: Write minimal implementation**

Add the urgency constant near `@page_size`:

```elixir
  @urgency_window_days 365
```

Add the urgency clause and its helpers (place after the non-urgency `do_load_page/7`):

```elixir
  defp do_load_page(scope, today, status, :live, query, :urgency, cursor) do
    window_end = Date.add(today, @urgency_window_days)

    case decode_urgency_cursor(cursor) do
      {:window, offset} -> serve_window(scope, today, status, query, window_end, offset)
      {:tail, inner} -> serve_tail(scope, today, status, query, window_end, inner)
    end
  end

  defp serve_window(scope, today, status, query, window_end, offset) do
    ranked =
      scope
      |> Obligations.list_obligations_page(
        status: status,
        query: query,
        sort: :due_asc,
        due_before: window_end,
        limit: :all
      )
      |> Map.fetch!(:rows)
      |> build_rows(today)
      |> Enum.sort_by(fn %{obligation: o, urgency: u} ->
        {@urgency_rank[u], Date.to_iso8601(o.due_by)}
      end)

    page = Enum.slice(ranked, offset, @page_size)
    next_offset = offset + @page_size

    if next_offset < length(ranked) do
      %{rows: page, cursor: encode_urgency_cursor({:window, next_offset}), end?: false}
    else
      # Window exhausted; hand off to the > window_end tail (may be empty).
      %{rows: page, cursor: encode_urgency_cursor({:tail, nil}), end?: false}
    end
  end

  defp serve_tail(scope, today, status, query, window_end, inner_cursor) do
    page =
      Obligations.list_obligations_page(scope,
        status: status,
        query: query,
        sort: :due_asc,
        due_after: window_end,
        cursor: inner_cursor
      )

    cursor = if page.end?, do: nil, else: encode_urgency_cursor({:tail, page.cursor})
    %{rows: build_rows(page.rows, today), cursor: cursor, end?: page.end?}
  end

  defp decode_urgency_cursor(nil), do: {:window, 0}

  defp decode_urgency_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, decoded} <- Jason.decode(json) do
      case decoded do
        %{"m" => "w", "o" => offset} -> {:window, offset}
        %{"m" => "t", "c" => inner} -> {:tail, inner}
        _ -> {:window, 0}
      end
    else
      _ -> {:window, 0}
    end
  end

  defp encode_urgency_cursor({:window, offset}),
    do: %{"m" => "w", "o" => offset} |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp encode_urgency_cursor({:tail, inner}),
    do: %{"m" => "t", "c" => inner} |> Jason.encode!() |> Base.url_encode64(padding: false)
```

(`inner` is the inner Pagination-encoded string or `nil`; `list_obligations_page` decodes `nil` as the first page.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/live/index_helpers_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/obligation_live/index_helpers.ex test/tugas_web/live/index_helpers_test.exs
git commit -m "feat: urgency window + tail paging for live dashboard sort

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Desktop dashboard — streams, sort control, infinite scroll

**Files:**
- Modify: `lib/tugas_web/live/dashboard_live/index.ex`
- Test: `test/tugas_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `DashboardFilter.assign_filters/2` (now assigns `:sort`), `DashboardFilter.persist/1`, `IndexHelpers.load_page/7`, `IndexHelpers.sorts/1`, `IndexHelpers.parse_sort/1`.

- [ ] **Step 1: Write the failing test**

Add to `test/tugas_web/live/dashboard_live_test.exs`:

```elixir
  test "sort dropdown reorders, hides urgency off-live, and infinite scroll appends", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    for i <- 1..30 do
      {:ok, _} =
        Obligations.create_obligation(manager, %{
          title: "Duty #{String.pad_leading(Integer.to_string(i), 2, "0")}",
          obligation_type_id: type.id,
          due_by: Date.add(~D[2026-06-01], i),
          open_note: "n"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    # First page caps at 25.
    assert view |> element("#obligations-list") |> render() =~ "Duty 25"
    refute view |> element("#obligations-list") |> render() =~ "Duty 26"

    # Infinite scroll reveals the rest.
    render_hook(view, "load_more", %{})
    assert view |> element("#obligations-list") |> render() =~ "Duty 26"

    # Urgency option present on live.
    assert has_element?(view, "#obligation-sort option[value='urgency']")

    # Switching to Completed hides urgency.
    view |> form("#obligation-status-filter", %{lifecycle: "completed"}) |> render_change()
    refute has_element?(view, "#obligation-sort option[value='urgency']")
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs -k "infinite scroll"`
Expected: FAIL (`#obligation-sort` missing, `load_more` not handled, no 25-cap).

- [ ] **Step 3: Write minimal implementation**

In `lib/tugas_web/live/dashboard_live/index.ex`:

Replace the list markup (the `<ul id="obligations-list">` block) with a stream + sentinel + separate empty state:

```heex
        <div class="tugas-page-body">
          <ul
            id="obligations-list"
            class="tugas-row-list"
            phx-update="stream"
            phx-viewport-bottom={!@end? && "load_more"}
          >
            <li
              :for={{dom_id, row} <- @streams.rows}
              id={dom_id}
              data-event-count={row.event_count}
              data-event-status={row.latest_event && row.latest_event.status}
            >
              <.obligation_row_link row={row} slug={@current_scope.entity.slug} today={@today} />
            </li>
          </ul>
          <div
            :if={@empty?}
            id="obligations-empty"
            class="py-8 text-center text-base-content/60"
          >
            {Index.empty_message(@mine?, @lifecycle)}
          </div>
        </div>
```

Add the sort `<select>` to the controls row, right after the `#obligation-status-filter` form:

```heex
            <form id="obligation-sort-filter" phx-change="set_sort">
              <select id="obligation-sort" name="sort" class="select select-sm">
                <option
                  :for={{value, label} <- Index.sorts(@lifecycle)}
                  value={value}
                  selected={@sort == Index.parse_sort(value)}
                >
                  {label}
                </option>
              </select>
            </form>
```

Rewrite `mount/3` to seed pagination and the first page:

```elixir
  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> DashboardFilter.assign_filters(session)
     |> load_first_page()}
  end
```

Replace the four mutating handlers and `load_rows/1` with first-page reloads + a `load_more` handler:

```elixir
  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket
     |> assign(:mine?, mine == "true")
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("set_status", %{"lifecycle" => lifecycle}, socket) do
    {:noreply,
     socket
     |> assign(:lifecycle, Index.parse_lifecycle(lifecycle))
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(:sort, Index.parse_sort(sort))
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("load_more", _params, socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort,
      cursor: cursor
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, cursor)

    {:noreply,
     socket
     |> stream(:rows, rows, dom_id: &row_dom_id/1, at: -1)
     |> assign(cursor: cursor, end?: end?)}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_first_page(socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, nil)

    socket
    |> stream(:rows, rows, dom_id: &row_dom_id/1, reset: true)
    |> assign(cursor: cursor, end?: end?, empty?: rows == [])
  end

  defp row_dom_id(row), do: "obligation-row-#{row.obligation.id}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/live/dashboard_live_test.exs`
Expected: PASS (new test + the existing persistence/scope tests, which still find `#scope-mine.tab-active`, `#obligation-search`, and `#obligations-empty`).

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/dashboard_live/index.ex test/tugas_web/live/dashboard_live_test.exs
git commit -m "feat: sort control and infinite scroll on the desktop dashboard

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Mobile dashboard — streams, sort control, infinite scroll

**Files:**
- Modify: `lib/tugas_web/live/mobile_live/dashboard.ex`
- Modify: `lib/tugas_web/live/mobile_live/components.ex`
- Test: `test/tugas_web/live/mobile_live_test.exs`

**Interfaces:**
- Consumes: same IndexHelpers / DashboardFilter functions as Task 7.
- Produces: `obligation_card/1` gains a required `id` attr used on its root `<li>`.

- [ ] **Step 1: Write the failing test**

Add to `test/tugas_web/live/mobile_live_test.exs`:

```elixir
  test "mobile sort dropdown reorders and infinite scroll appends", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    for i <- 1..30 do
      {:ok, _} =
        Tugas.Obligations.create_obligation(manager, %{
          title: "Duty #{String.pad_leading(Integer.to_string(i), 2, "0")}",
          obligation_type_id: type.id,
          due_by: Date.add(~D[2026-06-01], i),
          open_note: "n"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert view |> element("#mobile-obligations") |> render() =~ "Duty 25"
    refute view |> element("#mobile-obligations") |> render() =~ "Duty 26"

    render_hook(view, "load_more", %{})
    assert view |> element("#mobile-obligations") |> render() =~ "Duty 26"

    assert has_element?(view, "#m-obligation-sort option[value='urgency']")
  end
```

Confirm `mobile_conn/2` and `type_fixture/1` are already imported in this test module (they are used by existing tests / fixtures). If `type_fixture` is not imported, add `import Tugas.ObligationsFixtures` at the top.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/mobile_live_test.exs -k "infinite scroll"`
Expected: FAIL (`#m-obligation-sort` missing, `load_more` not handled).

- [ ] **Step 3: Write minimal implementation**

In `lib/tugas_web/live/mobile_live/components.ex`, add the `id` attr and use it on the root `<li>`:

```elixir
  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "%{obligation: ..., urgency: ..., cycle_status: ...}"
  attr :today, Date, required: true
  attr :slug, :string, required: true

  def obligation_card(assigns) do
    ~H"""
    <li
      id={@id}
      data-event-count={@row.event_count}
      data-event-status={@row.latest_event && @row.latest_event.status}
    >
```

(Leave the rest of the card unchanged.)

In `lib/tugas_web/live/mobile_live/dashboard.ex`, add the sort `<select>` to the header controls row (after the `#m-obligation-status-filter` form):

```heex
          <form id="m-obligation-sort-filter" phx-change="set_sort">
            <select id="m-obligation-sort" name="sort" class="select select-sm">
              <option
                :for={{value, label} <- Index.sorts(@lifecycle)}
                value={value}
                selected={@sort == Index.parse_sort(value)}
              >
                {label}
              </option>
            </select>
          </form>
```

Replace the `<ul id="mobile-obligations">` block with a stream + sentinel + empty state:

```heex
      <ul
        id="mobile-obligations"
        class="px-4 space-y-2"
        phx-update="stream"
        phx-viewport-bottom={!@end? && "load_more"}
      >
        <.obligation_card
          :for={{dom_id, row} <- @streams.rows}
          id={dom_id}
          row={row}
          today={@today}
          slug={@current_scope.entity.slug}
        />
      </ul>
      <div
        :if={@empty?}
        id="m-obligations-empty"
        class="text-center text-base-content/60 py-12"
      >
        {Index.empty_message(@mine?, @lifecycle)}
      </div>
```

Rewrite `mount/3` and the handlers exactly as in Task 7 but with the mobile `row_dom_id/1`:

```elixir
  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Tugas.Obligations.Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> DashboardFilter.assign_filters(session)
     |> load_first_page()}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket |> assign(:mine?, mine == "true") |> load_first_page() |> DashboardFilter.persist()}
  end

  def handle_event("set_status", %{"lifecycle" => lifecycle}, socket) do
    {:noreply,
     socket
     |> assign(:lifecycle, Index.parse_lifecycle(lifecycle))
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply,
     socket |> assign(:sort, Index.parse_sort(sort)) |> load_first_page() |> DashboardFilter.persist()}
  end

  def handle_event("search", params, socket) do
    query = Map.get(params, "value") || Map.get(params, "q") || ""

    {:noreply,
     socket |> assign(:query, query) |> load_first_page() |> DashboardFilter.persist()}
  end

  def handle_event("load_more", _params, socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort,
      cursor: cursor
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, cursor)

    {:noreply,
     socket
     |> stream(:rows, rows, dom_id: &row_dom_id/1, at: -1)
     |> assign(cursor: cursor, end?: end?)}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_first_page(socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, nil)

    socket
    |> stream(:rows, rows, dom_id: &row_dom_id/1, reset: true)
    |> assign(cursor: cursor, end?: end?, empty?: rows == [])
  end

  defp row_dom_id(row), do: "m-ob-#{row.obligation.id}"
```

Remove the old `load_rows/1` from this module.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas_web/live/mobile_live_test.exs`
Expected: PASS (new test + existing mobile persistence/render tests).

- [ ] **Step 5: Commit**

```bash
git add lib/tugas_web/live/mobile_live/dashboard.ex lib/tugas_web/live/mobile_live/components.ex test/tugas_web/live/mobile_live_test.exs
git commit -m "feat: sort control and infinite scroll on the mobile dashboard

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Wire the JS push payload + full-suite gate

**Files:**
- Verify: `assets/js/app.js` (the `store-dashboard-filter` handler already forwards `event.detail` via `URLSearchParams`, so the new `sort` key flows with no change).
- Run: full precommit.

- [ ] **Step 1: Confirm the JS forwards `sort`**

Read `assets/js/app.js` and confirm the `phx:store-dashboard-filter` listener posts `new URLSearchParams(event.detail)` — `sort` is part of `event.detail` from Task 4's `push_event`, so no edit is needed. If the handler hardcodes keys instead of spreading `event.detail`, update it to include `sort`.

- [ ] **Step 2: Run the full suite + format + warnings gate**

Run: `mix precommit`
Expected: PASS (compile `--warnings-as-errors`, `deps.unlock --unused`, `format`, full `mix test`).

- [ ] **Step 3: Commit any formatting/cleanup**

```bash
git add -A
git commit -m "chore: precommit gate for dashboard sort + infinite scroll

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

(If `git status` is clean after `mix precommit`, skip this commit.)

---

## Self-Review

**Spec coverage:**
- SQL filter + sort + keyset paging for all lifecycles → Tasks 1–3.
- `sort` persistence (default `due_asc`, reject bogus) → Task 4.
- Lifecycle-aware dropdown (urgency only on Live), `effective_sort` downgrade → Tasks 5, 7, 8.
- Presets due_asc/due_desc/title/urgency → Tasks 2, 5, 6.
- Urgency = in-memory, 1-year window + SQL tail → Task 6.
- Streams + `phx-viewport-bottom` + preserved DOM ids + mobile card `id` → Tasks 7, 8.
- Empty state via `@empty?` → Tasks 7, 8.
- Keyset indexes → Task 3.
- JS payload carries `sort` → Task 9.

**Placeholder scan:** every code step contains complete code; no TBD/TODO. The urgency two-mode cursor, the search escaping, and the `limit: :all` path are all spelled out.

**Type consistency:** `load_page/7` signature `(scope, today, mine?, lifecycle, query, sort, cursor)` is identical across IndexHelpers (Tasks 5/6) and both LiveViews (Tasks 7/8). `list_obligations_page/2` option names (`:status`, `:query`, `:sort`, `:cursor`, `:limit`, `:due_before`, `:due_after`) match between Tasks 2 and 6. Cursor is an opaque string in both the Pagination codec (Task 1) and the urgency wrapper (Task 6); `Pagination.decode/1` accepts string|map|nil so the nested/passed-through cursors are safe. `row_dom_id/1` is defined per-LiveView with the matching id prefix (`obligation-row-`, `m-ob-`).
