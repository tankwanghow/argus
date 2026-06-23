# Someday (no-due-date) duties — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a duty have no due date ("Someday"), surfaced in its own dashboard tab and kept out of the urgency/deadline views.

**Architecture:** `due_by` becomes nullable; "Someday" is exactly `due_by IS NULL` on a live cycle. The dashboard splits the live set into **Live** (dated) and **Someday** (dateless); urgency/recurrence are guarded to be no-ops without a date; a `recent` (inserted_at) sort and a nullable-`due_by` keyset handle ordering.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8.5 / LiveView 1.2.1 / Ecto 3.13 / PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-06-23-someday-no-due-date-duties-design.md`.

## Global Constraints

- The core liveness predicate `Obligations.live/1` (`completed_at IS NULL AND closed_at IS NULL`) is **unchanged**.
- **Live** = live `AND due_by IS NOT NULL`; **Someday** = live `AND due_by IS NULL`. This split lives only in `list_obligations_page/2`; the older `list_obligations/2` and its `:live` semantics are untouched.
- "Someday" is **not a new column** — it is `due_by IS NULL`. A virtual `:someday` boolean drives the create/edit changeset only.
- Status dropdown order: `Live · Someday · Completed · Skipped · All`. Default lifecycle stays **Live**.
- Sort preset values: `due_asc | due_desc | title | urgency | recent`. The Someday tab offers only `recent` (default) and `title`.
- Dateless rows show **no countdown badge, no color border, no "due …" text**. `Urgency.classify/tier` return `:none` for a nil `due_by`.
- `complete`/`skip` require `next_due_by` and spawn a successor **only when the cycle had a `due_by`**.
- A dateless duty of a recurring type is allowed (it just won't recur until dated).
- Run `mix precommit` before declaring the feature done.
- Commit message bodies end with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## File Structure

- Create: `priv/repo/migrations/<ts>_make_obligation_due_by_nullable.exs`.
- Modify: `lib/argus/obligations/obligation.ex` — nullable-aware changeset + `:someday` virtual field.
- Modify: `lib/argus/obligations.ex` — `validate_next_due/2` + `should_spawn_next?/2` date guard; `list_obligations_page/2` someday status + nullable keyset + `recent` sort.
- Modify: `lib/argus/obligations/urgency.ex` — nil `due_by` → `:none`.
- Modify: `lib/argus_web/components/urgency_badge.ex` — defensive nil/`:none` clause.
- Modify: `lib/argus_web/live/obligation_live/index_helpers.ex` — `:someday` lifecycle, `recent` sort, `sorts/1`, `effective_sort/2`, labels, empty message.
- Modify: `lib/argus_web/dashboard_filter.ex` — `@sorts`/`@lifecycles` whitelists.
- Modify: `lib/argus_web/live/dashboard_live/index.ex` + `lib/argus_web/live/mobile_live/components.ex` — hide date/urgency chrome for dateless rows.
- Modify: `lib/argus_web/live/obligation_live/create_form.ex`, `.../obligation_live/form.ex`, `.../mobile_live/obligation_form.ex` — "No due date" toggle.
- Modify: `lib/argus_web/live/obligation_live/show.ex` + `.../mobile_live/obligation_show.ex` — date/urgency guards + edit-form Someday toggle (promote/demote).
- Tests alongside each.

---

### Task 1: Nullable `due_by` + conditional-required changeset

**Files:**
- Create: `priv/repo/migrations/<ts>_make_obligation_due_by_nullable.exs`
- Modify: `lib/argus/obligations/obligation.ex`
- Test: `test/argus/obligations_test.exs`

**Interfaces:**
- Produces: `Obligation` gains a virtual `field :someday, :boolean`. `Obligation.changeset/2` requires `due_by` **unless** `someday` is truthy, and force-nils `due_by` when `someday` is truthy. `due_by` column is nullable.

- [ ] **Step 1: Generate the migration**

Run: `mix ecto.gen.migration make_obligation_due_by_nullable`

- [ ] **Step 2: Write the migration body**

```elixir
defmodule Argus.Repo.Migrations.MakeObligationDueByNullable do
  use Ecto.Migration

  def change do
    alter table(:obligations) do
      modify :due_by, :date, null: true, from: {:date, null: false}
    end
  end
end
```

- [ ] **Step 3: Migrate**

Run: `mix ecto.migrate`
Expected: applies cleanly.

- [ ] **Step 4: Write the failing test**

Add to `test/argus/obligations_test.exs` inside `describe "Obligation.changeset/2"`:

```elixir
    test "requires due_by normally" do
      cs = Obligation.changeset(%Obligation{}, %{title: "t", obligation_type_id: Ecto.UUID.generate()})
      refute cs.valid?
      assert %{due_by: ["can't be blank"]} = errors_on(cs)
    end

    test "someday=true makes due_by optional and force-nils it" do
      cs =
        Obligation.changeset(%Obligation{}, %{
          title: "t",
          obligation_type_id: Ecto.UUID.generate(),
          due_by: ~D[2026-01-01],
          someday: true
        })

      refute Keyword.has_key?(cs.errors, :due_by)
      assert Ecto.Changeset.get_field(cs, :due_by) == nil
    end
```

- [ ] **Step 5: Run test to verify it fails**

Run: `mix test test/argus/obligations_test.exs -k "someday"`
Expected: FAIL (no `:someday` field; due_by still required).

- [ ] **Step 6: Implement the changeset**

In `lib/argus/obligations/obligation.ex`, add the virtual field (near the other fields):

```elixir
    field :someday, :boolean, virtual: true
```

Add `:someday` to `@cast_fields`:

```elixir
  @cast_fields ~w(title obligation_type_id primary_assignee_id due_by open_note someday)a
```

Rewrite `changeset/2`:

```elixir
  def changeset(obligation, attrs) do
    obligation
    |> cast(attrs, @cast_fields)
    |> maybe_clear_due_by()
    |> validate_required([:title, :obligation_type_id])
    |> validate_due_by()
    |> validate_length(:title, max: 60)
    |> normalize_blank_assignee()
    |> unique_constraint(:series_id, name: :obligations_one_live_cycle_per_series)
  end

  defp maybe_clear_due_by(changeset) do
    if get_field(changeset, :someday) do
      put_change(changeset, :due_by, nil)
    else
      changeset
    end
  end

  defp validate_due_by(changeset) do
    if get_field(changeset, :someday) do
      changeset
    else
      validate_required(changeset, [:due_by])
    end
  end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/argus/obligations_test.exs`
Expected: PASS (existing changeset tests + the two new ones).

- [ ] **Step 8: Commit**

```bash
git add priv/repo/migrations/*_make_obligation_due_by_nullable.exs lib/argus/obligations/obligation.ex test/argus/obligations_test.exs
git commit -m "feat: allow obligations with no due date (Someday)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Recurrence guard — dateless cycles never require/spawn next

**Files:**
- Modify: `lib/argus/obligations.ex`
- Test: `test/argus/obligations_test.exs`

**Interfaces:**
- Consumes: Task 1 (a duty may have `due_by == nil`).
- Produces: `complete/3` and `skip/3` on a cycle with `due_by == nil` neither require `next_due_by` nor spawn a successor, even for a recurring type.

- [ ] **Step 1: Write the failing test**

Add to `test/argus/obligations_test.exs`:

```elixir
  describe "complete/skip on a dateless cycle" do
    test "completing a dateless recurring duty needs no next_due and spawns nothing" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, ob} =
        Obligations.create_obligation(manager, %{
          title: "Someday recurring",
          obligation_type_id: type.id,
          someday: true,
          open_note: "n"
        })

      assert ob.due_by == nil
      assert {:ok, _completed, nil} = Obligations.complete(manager, ob, %{note: "done"})
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus/obligations_test.exs -k "dateless"`
Expected: FAIL with `{:error, :next_due_required}` (recurring + no next_due).

- [ ] **Step 3: Add the date guard**

In `lib/argus/obligations.ex`, add `not is_nil(obligation.due_by)` to both guards.

`validate_next_due/2`:

```elixir
  defp validate_next_due(%Obligation{} = obligation, attrs) do
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    type = obligation.obligation_type || Repo.get!(Type, obligation.obligation_type_id)

    if not is_nil(obligation.due_by) and Recurrence.recurring?(type) and
         not Series.ended?(obligation.series_id) and next_due_by in [nil, ""] do
      {:error, :next_due_required}
    else
      :ok
    end
  end
```

`should_spawn_next?/2`:

```elixir
  defp should_spawn_next?(%Obligation{} = obligation, next_due_by) do
    not is_nil(obligation.due_by) and Recurrence.recurring?(obligation.obligation_type) and
      not Series.ended?(obligation.series_id) and not is_nil(next_due_by)
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus/obligations_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus/obligations.ex test/argus/obligations_test.exs
git commit -m "feat: dateless duties complete/skip as one-offs (no recurrence)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Urgency nil-guards

**Files:**
- Modify: `lib/argus/obligations/urgency.ex`
- Modify: `lib/argus_web/components/urgency_badge.ex`
- Test: `test/argus/obligations/urgency_test.exs`

**Interfaces:**
- Produces: `Urgency.classify(type, nil, today) :: :none`; `Urgency.tier(type, nil, today) :: :none`. `UrgencyBadge.badge_text/3` returns `nil` for a nil `due_by` (defensive; templates also guard).

- [ ] **Step 1: Write the failing test**

Add to `test/argus/obligations/urgency_test.exs` (create the file if missing; use the existing test module name if present):

```elixir
  test "classify and tier return :none when due_by is nil" do
    type = %Argus.Obligations.Type{reminder_offsets: "30,7,1"}
    assert Argus.Obligations.Urgency.classify(type, nil, ~D[2026-06-23]) == :none
    assert Argus.Obligations.Urgency.tier(type, nil, ~D[2026-06-23]) == :none
  end
```

(If `urgency_test.exs` does not exist, create it with `defmodule Argus.Obligations.UrgencyTest do use ExUnit.Case, async: true` … `end`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus/obligations/urgency_test.exs`
Expected: FAIL (`Date.compare(nil, …)`/`Date.diff(nil, …)` raises).

- [ ] **Step 3: Add the nil guards**

In `lib/argus/obligations/urgency.ex`, add a nil clause **before** each existing head:

```elixir
  def classify(%Type{}, nil, _today), do: :none

  def tier(%Type{}, nil, _today), do: :none
```

In `lib/argus_web/components/urgency_badge.ex`, add a nil clause **before** the catch-all `badge_text/3`:

```elixir
  def badge_text(_tier, nil, _today), do: nil
```

(`tier_border/1` already falls through to `border-transparent` for `:none`, and `badge_class/1`'s catch-all returns `""` — no change needed.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus/obligations/urgency_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus/obligations/urgency.ex lib/argus_web/components/urgency_badge.ex test/argus/obligations/urgency_test.exs
git commit -m "feat: urgency is :none for dateless duties

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `list_obligations_page/2` — Someday status, `recent` sort, nullable keyset

**Files:**
- Modify: `lib/argus/obligations.ex`
- Test: `test/argus/obligations_test.exs`

**Interfaces:**
- Consumes: Task 1 (nullable `due_by`).
- Produces: `list_obligations_page/2` accepts `status: :someday | :my_someday` (live + `due_by IS NULL`; `:live`/`:my_live` now also require `due_by IS NOT NULL` **in this function only**) and `sort: :recent` (`inserted_at` desc keyset). Date sorts on Completed/Skipped/All place dateless cycles **last** (`NULLS LAST`) and page across the null boundary without dup/skip.

- [ ] **Step 1: Write the failing test**

Add to `test/argus/obligations_test.exs`:

```elixir
  describe "list_obligations_page/2 — someday + nullable keyset" do
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

    test "live excludes dateless; someday returns only dateless", %{manager: m, dated: dated, someday: someday} do
      live = Obligations.list_obligations_page(m, status: :live, limit: :all)
      assert Enum.map(live.rows, & &1.id) |> Enum.sort() == Enum.map(dated, & &1.id) |> Enum.sort()

      sd = Obligations.list_obligations_page(m, status: :someday, sort: :recent, limit: :all)
      assert Enum.map(sd.rows, & &1.id) |> Enum.sort() == Enum.map(someday, & &1.id) |> Enum.sort()
    end

    test "recent sort orders newest-first with stable keyset paging", %{manager: m, someday: someday} do
      [x, y, z] = someday
      p1 = Obligations.list_obligations_page(m, status: :someday, sort: :recent, limit: 2)
      assert Enum.map(p1.rows, & &1.id) == [z.id, y.id]
      p2 = Obligations.list_obligations_page(m, status: :someday, sort: :recent, limit: 2, cursor: p1.cursor)
      assert Enum.map(p2.rows, & &1.id) == [x.id]
      assert p2.end?
    end

    test "completed date sort places dateless cycles last (NULLS LAST)", %{manager: m, dated: [da, _db], someday: [sx | _]} do
      # complete one dated and one dateless cycle
      {:ok, _, _} = Obligations.complete(m, da, %{note: "d"})
      {:ok, _, _} = Obligations.complete(m, sx, %{note: "d"})

      page = Obligations.list_obligations_page(m, status: :completed, sort: :due_asc, limit: :all)
      ids = Enum.map(page.rows, & &1.id)
      assert List.last(ids) == sx.id
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus/obligations_test.exs -k "someday + nullable"`
Expected: FAIL (`:someday` invalid status; `:recent` unknown; nil `due_by` cursor crash).

- [ ] **Step 3: Implement**

In `lib/argus/obligations.ex`:

Extend `@status_filters`:

```elixir
  @status_filters ~w(my_live my_completed my_skipped my_all my_someday live completed skipped all someday)a
```

Add `:someday` clauses to `apply_status_filter/2` (after the `:live` clause):

```elixir
  defp apply_status_filter(query, status) when status in [:someday, :my_someday] do
    from o in live(query), where: is_nil(o.due_by)
  end
```

In `list_obligations_page/2`, replace the `|> apply_status_filter(status)` call with `|> apply_page_status(status)`, and add:

```elixir
  defp apply_page_status(query, status) when status in [:live, :my_live] do
    query |> apply_status_filter(status) |> where([o], not is_nil(o.due_by))
  end

  defp apply_page_status(query, status), do: apply_status_filter(query, status)
```

Accept `:recent` in `normalize_page_sort/1`:

```elixir
  defp normalize_page_sort(sort) when sort in [:due_asc, :due_desc, :title, :recent], do: sort
  defp normalize_page_sort(_), do: :due_asc
```

Add the `recent` order + NULLS LAST for date sorts:

```elixir
  defp apply_page_order(query, :due_asc), do: order_by(query, [o], asc_nulls_last: o.due_by, asc: o.id)
  defp apply_page_order(query, :due_desc), do: order_by(query, [o], desc_nulls_last: o.due_by, asc: o.id)

  defp apply_page_order(query, :title),
    do: order_by(query, [o], asc: fragment("lower(?)", o.title), asc: o.id)

  defp apply_page_order(query, :recent), do: order_by(query, [o], desc: o.inserted_at, desc: o.id)
```

Add the `recent` cursor + a null-aware `cursor_key`/`apply_page_cursor` for the date sorts. Replace `cursor_key/2`:

```elixir
  @null_key " null"

  defp cursor_key(:title, %Obligation{title: t}), do: String.downcase(t)
  defp cursor_key(:recent, %Obligation{inserted_at: ts}), do: DateTime.to_iso8601(ts)
  defp cursor_key(_sort, %Obligation{due_by: nil}), do: @null_key
  defp cursor_key(_sort, %Obligation{due_by: d}), do: Date.to_iso8601(d)
```

Add the `:recent` cursor clause and null-aware date cursor clauses (replace the existing `:due_asc`/`:due_desc` clauses):

```elixir
  defp apply_page_cursor(query, :due_asc, %{key: @null_key, id: id}),
    do: where(query, [o], is_nil(o.due_by) and o.id > ^id)

  defp apply_page_cursor(query, :due_asc, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} ->
        where(query, [o], o.due_by > ^d or (o.due_by == ^d and o.id > ^id) or is_nil(o.due_by))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :due_desc, %{key: @null_key, id: id}),
    do: where(query, [o], is_nil(o.due_by) and o.id > ^id)

  defp apply_page_cursor(query, :due_desc, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} ->
        where(query, [o], o.due_by < ^d or (o.due_by == ^d and o.id > ^id) or is_nil(o.due_by))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :recent, %{key: k, id: id}) do
    case DateTime.from_iso8601(k) do
      {:ok, ts, _} ->
        where(query, [o], o.inserted_at < ^ts or (o.inserted_at == ^ts and o.id < ^id))

      _ ->
        query
    end
  end
```

(Keep the existing `apply_page_cursor(query, _sort, nil)` head first and the `:title` clause unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus/obligations_test.exs`
Expected: PASS (new describe + all existing list_obligations_page tests).

- [ ] **Step 5: Commit**

```bash
git add lib/argus/obligations.ex test/argus/obligations_test.exs
git commit -m "feat: Someday status, recent sort, nullable-due_by keyset paging

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Filter vocabulary — IndexHelpers + DashboardFilter

**Files:**
- Modify: `lib/argus_web/live/obligation_live/index_helpers.ex`
- Modify: `lib/argus_web/dashboard_filter.ex`
- Test: `test/argus_web/live/index_helpers_test.exs`

**Interfaces:**
- Produces: `IndexHelpers` recognises the `:someday` lifecycle and `:recent` sort. `sorts(:someday) -> [{"recent","Recently added"},{"title","Title A–Z"}]`; `effective_sort` coerces `recent` → `due_asc` off-Someday and any date/urgency sort → `recent` on Someday. `DashboardFilter` persists `recent`/`someday`.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/index_helpers_test.exs`:

```elixir
  test "someday lifecycle: status atom, label, sorts, effective_sort" do
    assert Index.status_atom(false, :someday) == :someday
    assert Index.status_atom(true, :someday) == :my_someday
    assert Index.parse_lifecycle("someday") == :someday
    assert Index.lifecycle_label(:someday) == "Someday"

    assert {"recent", "Recently added"} = List.keyfind(Index.sorts(:someday), "recent", 0)
    refute List.keyfind(Index.sorts(:someday), "urgency", 0)
    refute List.keyfind(Index.sorts(:live), "recent", 0)

    assert Index.effective_sort(:recent, :someday) == :recent
    assert Index.effective_sort(:recent, :live) == :due_asc
    assert Index.effective_sort(:due_asc, :someday) == :recent
    assert Index.parse_sort("recent") == :recent
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/index_helpers_test.exs`
Expected: FAIL (`:someday`/`:recent` unknown).

- [ ] **Step 3: Implement**

In `lib/argus_web/live/obligation_live/index_helpers.ex`:

Add `:someday` to `@lifecycles`:

```elixir
  @lifecycles ~w(live someday completed skipped all)a
```

Add label + parse + status_atom + empty_message clauses:

```elixir
  def parse_lifecycle("someday"), do: :someday
  # (keep the existing completed/skipped/all clauses; the catch-all stays last)

  def lifecycle_label(:someday), do: "Someday"

  def status_atom(true, :someday), do: :my_someday
  def status_atom(false, :someday), do: :someday

  def empty_message(mine?, :someday) do
    who = if mine?, do: " assigned to you", else: ""
    "No someday duties#{who}."
  end
```

(Place `parse_lifecycle("someday")` among the other string clauses, `lifecycle_label(:someday)` among the labels, the `status_atom` someday clauses before the generic `status_atom(false, lifecycle)`, and the `empty_message(_, :someday)` clause before the existing `case`-based one — or fold it in; ensure the `:someday` lifecycle is matched.)

Replace `sorts/1`, `parse_sort/1`, `effective_sort/2`:

```elixir
  def sorts(:live),
    do: [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}, {"urgency", "Most urgent"}, {"title", "Title A–Z"}]

  def sorts(:someday),
    do: [{"recent", "Recently added"}, {"title", "Title A–Z"}]

  def sorts(_lifecycle),
    do: [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}, {"title", "Title A–Z"}]

  def parse_sort("due_desc"), do: :due_desc
  def parse_sort("title"), do: :title
  def parse_sort("urgency"), do: :urgency
  def parse_sort("recent"), do: :recent
  def parse_sort(_), do: :due_asc

  def effective_sort(sort, lifecycle) do
    allowed = Enum.map(sorts(lifecycle), fn {v, _} -> parse_sort(v) end)
    if sort in allowed, do: sort, else: default_sort(lifecycle)
  end

  defp default_sort(:someday), do: :recent
  defp default_sort(_), do: :due_asc
```

In `lib/argus_web/dashboard_filter.ex`, extend the whitelists:

```elixir
  @lifecycles ~w(live someday completed skipped all)
  @sorts ~w(due_asc due_desc title urgency recent)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/live/index_helpers_test.exs test/argus_web/dashboard_filter_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/obligation_live/index_helpers.ex lib/argus_web/dashboard_filter.ex test/argus_web/live/index_helpers_test.exs
git commit -m "feat: Someday lifecycle + Recently-added sort in dashboard filters

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Dashboard rows hide date/urgency chrome for dateless duties

**Files:**
- Modify: `lib/argus_web/live/dashboard_live/index.ex`
- Modify: `lib/argus_web/live/mobile_live/components.ex`
- Test: `test/argus_web/live/dashboard_live_test.exs`, `test/argus_web/live/mobile_live_test.exs`

**Interfaces:**
- Consumes: Tasks 4/5 (Someday tab returns dateless rows; `urgency`/`tier` are `:none`).
- Produces: a live row with `due_by == nil` renders no urgency badge, no tier border, and no "due …" line; it still shows title · type · assignee · latest event.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/dashboard_live_test.exs`:

```elixir
  test "Someday tab lists dateless duties without urgency/due chrome", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, _} =
      Obligations.create_obligation(manager, %{
        title: "Tidy the archive", obligation_type_id: type.id, someday: true, open_note: "n"
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")
    view |> form("#obligation-status-filter", %{lifecycle: "someday"}) |> render_change()

    html = view |> element("#obligations-list") |> render()
    assert html =~ "Tidy the archive"
    refute html =~ "overdue"
    refute html =~ "due "
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/dashboard_live_test.exs -k "Someday tab"`
Expected: FAIL (the "due —" line and/or urgency badge render for the dateless row).

- [ ] **Step 3: Implement the guards**

In `lib/argus_web/live/dashboard_live/index.ex` `obligation_row_link/1`, tighten the three date-dependent spots to require `due_by`:

- The left-accent border:

```elixir
        if(@row.cycle_status == :live and @row.obligation.due_by, do: tier_border(@row.tier), else: "border-transparent")
```

- The urgency badge:

```elixir
        <.urgency_badge
          :if={@row.cycle_status == :live and @row.obligation.due_by}
          tier={@row.tier}
          due_by={@row.obligation.due_by}
          today={@today}
        />
```

- The "due …" meta line — wrap the `·` separator and the due text so they only show with a date:

```elixir
        <div :if={@row.obligation.due_by}>·</div>
        <div :if={@row.obligation.due_by} class="text-base-content/60">
          due {format_date(@row.obligation.due_by)}
        </div>
```

In `lib/argus_web/live/mobile_live/components.ex` `obligation_card/1`, apply the same guards: the `accent/1` left-border, the `urgency_badge` `:if`, and the `card_meta/1` due text. Update `card_meta/1` (and/or its template usage) so a nil `due_by` omits the due fragment; gate the urgency badge with `:if={@row.cycle_status == :live and @row.obligation.due_by}` and the accent via a nil-due_by → transparent branch in `accent/1`:

```elixir
  defp accent(%{cycle_status: status}) when status in [:skipped, :series_ended], do: "border-base-300"
  defp accent(%{cycle_status: :live, obligation: %{due_by: nil}}), do: "border-base-300"
  defp accent(%{cycle_status: :live, tier: tier}), do: tier_border(tier)
  defp accent(_), do: "border-base-300"
```

(Match the existing `accent/1` return values; the key addition is the dateless-live clause returning the neutral border. If `card_meta/1` builds a string containing the due date, add a nil-`due_by` branch that omits it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/live/dashboard_live_test.exs test/argus_web/live/mobile_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/dashboard_live/index.ex lib/argus_web/live/mobile_live/components.ex test/argus_web/live/dashboard_live_test.exs test/argus_web/live/mobile_live_test.exs
git commit -m "feat: dateless dashboard rows omit due/urgency chrome

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Create-form "No due date" toggle

**Files:**
- Modify: `lib/argus_web/live/obligation_live/create_form.ex`
- Modify: `lib/argus_web/live/obligation_live/form.ex`
- Modify: `lib/argus_web/live/mobile_live/obligation_form.ex`
- Test: `test/argus_web/live/obligation_live_test.exs`

**Interfaces:**
- Consumes: Task 1 (`:someday` changeset field).
- Produces: both create forms have a "No due date (Someday)" checkbox; checking it submits `someday=true` with a blank `due_by`, creating a dateless duty.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/obligation_live_test.exs`:

```elixir
  test "create form can make a Someday (no due date) duty", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/obligations/new")

    view
    |> form("#obligation-form", obligation: %{
      title: "Improve onboarding docs",
      obligation_type_id: type.id,
      someday: "true",
      due_by: "",
      open_note: "idea"
    })
    |> render_submit()

    ob = Argus.Obligations.list_obligations_page(manager, status: :someday, limit: :all).rows |> List.first()
    assert ob.title == "Improve onboarding docs"
    assert ob.due_by == nil
  end
```

(Confirm the desktop form's id is `#obligation-form`; if different, use the actual id.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "Someday"`
Expected: FAIL (`someday` not passed through; due_by required).

- [ ] **Step 3: Pass `someday` through CreateForm**

In `lib/argus_web/live/obligation_live/create_form.ex`, add `"someday"` to the kept keys in `map_create_params/1`:

```elixir
    |> Map.take([
      "title",
      "obligation_type_id",
      "primary_assignee_id",
      "due_by",
      "open_note",
      "collaborator_ids",
      "someday"
    ])
```

(`validate/2` already calls `change_obligation(params)` with the raw params, so the checkbox feeds live validation; no other change there.)

- [ ] **Step 4: Add the toggle to both form templates**

In `lib/argus_web/live/obligation_live/form.ex`, replace the due_by input with a Someday checkbox + a conditionally-shown date input:

```heex
          <.input
            field={@form[:someday]}
            type="checkbox"
            label="No due date (Someday)"
          />
          <.input
            :if={!someday?(@form)}
            field={@form[:due_by]}
            type="date"
            label="Due by"
            required
          />
```

Add a private helper to the same LiveView module:

```elixir
  defp someday?(form), do: Phoenix.HTML.Form.normalize_value("checkbox", form[:someday].value)
```

Apply the identical change to `lib/argus_web/live/mobile_live/obligation_form.ex` (its due_by input + the same `someday?/1` helper).

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/argus_web/live/obligation_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/argus_web/live/obligation_live/create_form.ex lib/argus_web/live/obligation_live/form.ex lib/argus_web/live/mobile_live/obligation_form.ex test/argus_web/live/obligation_live_test.exs
git commit -m "feat: create-form No-due-date (Someday) toggle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Show page — date guards + promote/demote toggle

**Files:**
- Modify: `lib/argus_web/live/obligation_live/show.ex`
- Modify: `lib/argus_web/live/mobile_live/obligation_show.ex`
- Test: `test/argus_web/live/obligation_live_test.exs`

**Interfaces:**
- Consumes: Tasks 1/3 (nullable `due_by`, `:none` urgency); `update_obligation/3` already runs `Obligation.changeset/2`, so clearing `due_by` (demote) and setting it (promote) work through the same conditional rule.
- Produces: the show page renders a dateless duty without crashing (no urgency badge, no "due" date) and the edit form carries the same "No due date" toggle so a manager/admin can promote/demote.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/obligation_live_test.exs`:

```elixir
  test "show page renders a Someday duty and can promote it to a due date", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, ob} =
      Obligations.create_obligation(manager, %{
        title: "Refresh brand assets", obligation_type_id: type.id, someday: true, open_note: "n"
      })

    {:ok, view, html} = live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{ob.id}")
    assert html =~ "Refresh brand assets"

    # promote: open edit, set a due date, clear someday
    view
    |> form("#edit-obligation-form", obligation: %{
      title: ob.title, due_by: "2026-09-01", someday: "false"
    })
    |> render_submit()

    assert Argus.Repo.reload(ob).due_by == ~D[2026-09-01]
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "promote"`
Expected: FAIL (show crashes on nil `due_by`, and/or the edit form has no someday toggle).

- [ ] **Step 3: Guard the show templates**

In `lib/argus_web/live/obligation_live/show.ex`:

- The due-date summary line (currently `{format_date(@obligation.due_by)}`) is safe (`format_date(nil)` → "—"), but wrap the urgency badge:

```elixir
              <.urgency_badge :if={@live? and @obligation.due_by} tier={@tier} due_by={@obligation.due_by} today={@today} />
```

- The completed-in-error replacement default (currently `value={Date.to_iso8601(@obligation.due_by)}`) must tolerate nil:

```elixir
              value={@obligation.due_by && Date.to_iso8601(@obligation.due_by)}
```

- In the edit form, replace the `due_by` input with the Someday toggle + conditional date input:

```heex
            <.input field={@edit_form[:someday]} type="checkbox" label="No due date (Someday)" />
            <.input :if={!someday?(@edit_form)} field={@edit_form[:due_by]} type="date" label="Due by" required />
```

Add the helper to the module:

```elixir
  defp someday?(form), do: Phoenix.HTML.Form.normalize_value("checkbox", form[:someday].value)
```

When building `@edit_form`, seed the `someday` virtual from the current state so the box reflects reality:

```elixir
  defp edit_changeset(obligation),
    do: Obligations.change_obligation(obligation, %{"someday" => is_nil(obligation.due_by)})
```

(Use `edit_changeset/1` wherever `@edit_form` is currently built from `change_obligation/1`.)

Apply the same three guards (urgency badge `:if`, any `Date.to_iso8601(due_by)` default, edit-form toggle + `someday?/1` + seeded `someday`) to `lib/argus_web/live/mobile_live/obligation_show.ex`. The mobile "Due …" line at the top should also hide when `due_by` is nil:

```heex
            <span :if={@obligation.due_by}><span class="text-warning">Due </span>{format_date(@obligation.due_by, :short)}</span>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/live/obligation_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the full gate**

Run: `mix precommit`
Expected: PASS (compile `--warnings-as-errors`, format, full suite).

- [ ] **Step 6: Commit**

```bash
git add lib/argus_web/live/obligation_live/show.ex lib/argus_web/live/mobile_live/obligation_show.ex test/argus_web/live/obligation_live_test.exs
git commit -m "feat: show page renders Someday duties; edit toggles due date

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Nullable `due_by` + conditional-required changeset → Task 1.
- Recurrence requires a date (no spawn/next_due when dateless) → Task 2.
- Urgency `:none` for nil `due_by` → Task 3.
- Someday status (`live + due_by IS NULL`), Live narrowed to dated, `recent` sort, nullable keyset (NULLS LAST) → Task 4.
- Lifecycle/sort vocabulary + persistence (`someday`, `recent`) → Task 5.
- Dateless rows hide due/urgency chrome → Task 6.
- Create-form Someday toggle → Task 7.
- Show-page guards + promote/demote → Task 8.
- Status order `Live · Someday · Completed · Skipped · All` → `@lifecycles` ordering in Task 5; dropdowns render via `Index.lifecycles/0` (existing) so the option appears automatically.

**Placeholder scan:** every code step carries complete code; the only "confirm the actual id" notes (Task 7 form id, Task 8 edit-form id) name a concrete fallback (verify against the template) rather than leaving logic unspecified.

**Type consistency:** `:someday`/`:my_someday` status atoms and the `:recent` sort atom are used identically across Tasks 4, 5; `effective_sort/2` + `default_sort/1` defined in Task 5 are consumed by the dashboards (already wired from the prior feature); `someday?/1` helper has the same definition in Tasks 7 and 8; the virtual `:someday` field (Task 1) is the single mechanism threaded through create (Task 7) and edit (Task 8).
