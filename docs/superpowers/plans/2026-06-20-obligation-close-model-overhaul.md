# Obligation Close-Model Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `status` string with timestamp-based terminal states (`completed_at`/`closed_at`/`series_ended_at`), make skip & end-series first-class self-describing events, and unify Cancel+Skip into a single **Skip** action.

**Architecture:** A cycle is **live** while `completed_at IS NULL AND closed_at IS NULL`. Done stamps `completed_at` (event `done`); Skip stamps `closed_at` (event `skipped`, spawns a successor only when recurring); End series stamps `closed_at`+`series_ended_at` (event `series_ended`). "Who did it" is read off the singular terminal event's `status_by_id`; no `*_by` columns. completed-in-error keeps its columns (it creates no event).

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 LiveView, Ecto 3.13, PostgreSQL (binary_id PKs), Tailwind v4 + daisyUI 5.

## Global Constraints

- Tugas is **not deployed**; schema may be changed freely. No data migration needed (dev/test DBs are recreated). See `docs/superpowers/specs/2026-06-20-obligation-close-model-overhaul-design.md`.
- **binary_id (UUID) PKs everywhere** via `use Tugas.Schema`.
- Contexts own domain logic; LiveViews call `Tugas.Obligations`/`Tugas.Authorization`, never `Repo`. Unauthorized mutations return **`:not_authorise`**.
- Multi-step writes use `Ecto.Multi`. The liveness guard is a conditional `update_all ... WHERE live` returning 0 rows ⇒ `{:error, :not_live}`.
- Every state transition **requires a note** (`validate_action_note`).
- TDD: write the failing test, watch it fail, implement, watch it pass, commit. Run `mix precommit` before declaring a task done.
- Single test file: `mix test path:line`. Full suite: `mix test`.

---

### Task 1: Add `skipped` & `series_ended` event statuses; centralize terminal statuses

**Files:**
- Modify: `lib/tugas/obligations/event.ex`
- Modify: `lib/tugas/obligations.ex` (`ensure_progressable/1`, ~line 925-931)
- Test: `test/tugas/obligations/event_test.exs` (create)

**Interfaces:**
- Produces: `Event.terminal_statuses/0 :: [String.t()]` returning `["done", "skipped", "series_ended"]`; `Event` changeset accepts statuses `open | in_progress | done | skipped | series_ended` (no `cancelled`).

- [ ] **Step 1: Write the failing test**

Create `test/tugas/obligations/event_test.exs`:

```elixir
defmodule Tugas.Obligations.EventTest do
  use ExUnit.Case, async: true

  alias Tugas.Obligations.Event

  test "terminal_statuses are the closing statuses" do
    assert Event.terminal_statuses() == ["done", "skipped", "series_ended"]
  end

  test "changeset accepts skipped and series_ended" do
    for status <- ["open", "in_progress", "done", "skipped", "series_ended"] do
      cs = Event.changeset(%Event{}, %{status: status, note: "n"})
      assert cs.valid?, "expected #{status} to be valid"
    end
  end

  test "changeset rejects the retired cancelled status" do
    refute Event.changeset(%Event{}, %{status: "cancelled"}).valid?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/obligations/event_test.exs`
Expected: FAIL — `Event.terminal_statuses/0 undefined` and `cancelled` still accepted.

- [ ] **Step 3: Update the Event schema**

In `lib/tugas/obligations/event.ex`, replace the `@statuses` line and changeset, and add `terminal_statuses/0`:

```elixir
  @statuses ~w(open in_progress done skipped series_ended)
  @terminal_statuses ~w(done skipped series_ended)

  @doc "Statuses that close a cycle (no further progress allowed)."
  def terminal_statuses, do: @terminal_statuses

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:status, :note])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
```

- [ ] **Step 4: Point `ensure_progressable/1` at the centralized list**

In `lib/tugas/obligations.ex`, change the closed-check (currently `e.status in ["done", "cancelled"]`):

```elixir
  defp ensure_progressable(%Obligation{} = obligation) do
    closed? =
      Event
      |> where([e], e.obligation_id == ^obligation.id and e.status in ^Event.terminal_statuses())
      |> Repo.exists?()

    if closed?, do: {:error, :not_live}, else: :ok
  end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/tugas/obligations/event_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/tugas/obligations/event.ex lib/tugas/obligations.ex test/tugas/obligations/event_test.exs
git commit -m "feat: add skipped/series_ended event statuses + Event.terminal_statuses/0"
```

---

### Task 2: Render Skipped / Series-ended in badge + event meta (additive)

**Files:**
- Modify: `lib/tugas_web/components/obligation_status_badge.ex`
- Modify: `lib/tugas_web/components/event_meta.ex`
- Test: `test/tugas_web/components/obligation_status_badge_test.exs` (create)

**Interfaces:**
- Consumes: `obligation_status_badge/1` `:cycle_status` now also accepts `:skipped` and `:series_ended`.
- Produces: badge text "Skipped" (warning) and "Series ended" (neutral); `EventMeta` humanizes `skipped`/`series_ended`.

- [ ] **Step 1: Write the failing test**

Create `test/tugas_web/components/obligation_status_badge_test.exs`:

```elixir
defmodule TugasWeb.ObligationStatusBadgeTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import TugasWeb.ObligationStatusBadge

  test "renders a Skipped badge" do
    html = render_component(&obligation_status_badge/1, cycle_status: :skipped, in_error: false)
    assert html =~ "Skipped"
  end

  test "renders a Series ended badge" do
    html = render_component(&obligation_status_badge/1, cycle_status: :series_ended, in_error: false)
    assert html =~ "Series ended"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/components/obligation_status_badge_test.exs`
Expected: FAIL — neither string rendered.

- [ ] **Step 3: Add the badge clauses**

In `lib/tugas_web/components/obligation_status_badge.ex`, add inside the `~H` template (after the existing `:cancelled` span):

```elixir
    <span :if={@cycle_status == :skipped} class="badge badge-warning badge-sm">Skipped</span>
    <span :if={@cycle_status == :series_ended} class="badge badge-neutral badge-sm">
      Series ended
    </span>
```

- [ ] **Step 4: Add EventMeta labels/colors**

In `lib/tugas_web/components/event_meta.ex`, extend the private helpers (keep existing clauses):

```elixir
  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status("series_ended"), do: "Series ended"
  defp humanize_status(status), do: String.capitalize(status)

  defp status_badge_class("in_progress"), do: "badge-warning badge-soft"
  defp status_badge_class("done"), do: "badge-success badge-soft"
  defp status_badge_class("skipped"), do: "badge-warning badge-soft"
  defp status_badge_class("series_ended"), do: "badge-neutral badge-soft"
  defp status_badge_class(_), do: "badge-ghost"
```

(`humanize_status("skipped")` → "Skipped" via the catch-all `String.capitalize/1`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/tugas_web/components/obligation_status_badge_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/tugas_web/components/obligation_status_badge.ex lib/tugas_web/components/event_meta.ex test/tugas_web/components/obligation_status_badge_test.exs
git commit -m "feat: Skipped / Series ended badge + event-meta labels"
```

---

### Task 3: Schema + domain cutover (`status` → `closed_at`, unify Skip, retire Cancel)

This is the atomic core. After it, no code references `status`; `skip/3` is the single non-Done/non-end-series close; the dashboards/show pages keep working (handlers repointed); all affected tests are migrated.

**Files:**
- Create: `priv/repo/migrations/20260620000000_replace_status_with_closed_at.exs`
- Modify: `lib/tugas/obligations/obligation.ex` (schema + changeset)
- Modify: `lib/tugas/obligations.ex` (`live/1`, `apply_status_filter/2`, `spawn_next_cycle`, replace `cancel_obligation`+`skip_cycle` with `skip`, `end_series`, `validate_correctable`, `locked_cycle?`)
- Modify: `lib/tugas/authorization.ex`
- Modify: `lib/tugas_web/live/obligation_live/index_helpers.ex` (`cycle_status`)
- Modify: `lib/tugas_web/live/obligation_live/show.ex` and `lib/tugas_web/live/mobile_live/obligation_show.ex` (repoint domain calls + `can?` keys + result-tuple matches; keep existing buttons)
- Test: `test/tugas/obligations_test.exs`, `test/tugas/authorization_test.exs`, and any LiveView test asserting cancelled

**Interfaces:**
- Consumes: `Event.terminal_statuses/0` (Task 1); `:skipped`/`:series_ended` badges (Task 2).
- Produces:
  - `Obligations.skip(scope, obligation, %{note, next_due_by?}) :: {:ok, Obligation.t(), Obligation.t() | nil} | {:error, term} | :not_authorise` — closes the cycle (`closed_at`), inserts a `skipped` event, spawns the next cycle (3rd element) when recurring & not series-ended (then `next_due_by` required), else `nil`.
  - `Obligations.end_series(scope, obligation, %{note}) :: {:ok, Obligation.t()} | {:error, term} | :not_authorise` — stamps `closed_at`+`series_ended_at`, inserts `series_ended` event.
  - `Authorization.can?(scope, :skip)` (replaces `:cancel_obligation` and `:skip_cycle`).
  - `Obligation` columns: `closed_at` added, `status` removed.

- [ ] **Step 1: Write the migration**

Create `priv/repo/migrations/20260620000000_replace_status_with_closed_at.exs`:

```elixir
defmodule Tugas.Repo.Migrations.ReplaceStatusWithClosedAt do
  use Ecto.Migration

  def up do
    drop index(:obligations, [:entity_id, :status])

    drop unique_index(:obligations, [:series_id],
           name: :obligations_one_live_cycle_per_series)

    alter table(:obligations) do
      add :closed_at, :utc_datetime
      remove :status
    end

    create index(:obligations, [:entity_id])

    create unique_index(:obligations, [:series_id],
             where: "completed_at IS NULL AND closed_at IS NULL",
             name: :obligations_one_live_cycle_per_series)
  end

  def down do
    drop unique_index(:obligations, [:series_id],
           name: :obligations_one_live_cycle_per_series)

    drop index(:obligations, [:entity_id])

    alter table(:obligations) do
      add :status, :string, null: false, default: "active"
      remove :closed_at
    end

    create index(:obligations, [:entity_id, :status])

    create unique_index(:obligations, [:series_id],
             where: "status = 'active' AND completed_at IS NULL",
             name: :obligations_one_live_cycle_per_series)
  end
end
```

- [ ] **Step 2: Update the Obligation schema**

In `lib/tugas/obligations/obligation.ex`: remove `field :status, :string, default: "active"`, add `field :closed_at, :utc_datetime` (next to `completed_at`), and delete the `|> validate_inclusion(:status, ["active", "cancelled"])` line from the changeset.

- [ ] **Step 3: Migrate the DB and run the existing suite to see the breakage surface**

Run: `mix ecto.migrate && mix test 2>&1 | tail -30`
Expected: compile errors / failures everywhere `status` is referenced — this is the work list for the rest of the task.

- [ ] **Step 4: Update `live/1`**

In `lib/tugas/obligations.ex` (~line 27):

```elixir
  def live(query \\ Obligation) do
    from(o in query, where: is_nil(o.completed_at) and is_nil(o.closed_at))
  end
```

(Keep the existing arity/signature; only the `where` changes.)

- [ ] **Step 5: Update the list status filter**

Replace the `:cancelled` clause of `apply_status_filter/2` (~line 181):

```elixir
  defp apply_status_filter(query, :skipped) do
    from o in query, where: not is_nil(o.closed_at)
  end
```

- [ ] **Step 6: Drop `status: "active"` from spawn**

In `spawn_next_cycle/4`, remove `status: "active"` from the `%Obligation{...}` struct literal (leave `entity_id`, `series_id`, `complete_documents`).

- [ ] **Step 7: Write the failing tests for `skip/3` and `end_series/3`**

Add to `test/tugas/obligations_test.exs` (uses existing fixtures `manager_obligation_scope_fixture/0`, `recurring_manager_scope_fixture/1`):

```elixir
  describe "skip/3" do
    test "one-off skip closes the cycle with a skipped event, no successor" do
      {scope, obligation} = manager_obligation_scope_fixture()

      assert {:ok, closed, nil} = Obligations.skip(scope, obligation, %{note: "drop it"})
      assert closed.closed_at
      assert is_nil(closed.completed_at)

      events = Obligations.list_events(scope, closed.id)
      assert Enum.any?(events, &(&1.status == "skipped" and &1.note == "drop it"))
      assert Obligations.list_obligations(scope, status: :live) |> Enum.all?(&(&1.id != closed.id))
    end

    test "recurring skip requires next_due_by and spawns the next cycle" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} = Obligations.skip(scope, obligation, %{note: "skip"})

      assert {:ok, closed, %Tugas.Obligations.Obligation{} = spawned} =
               Obligations.skip(scope, obligation, %{note: "skip", next_due_by: ~D[2026-08-01]})

      assert closed.closed_at
      assert spawned.series_id == closed.series_id
      assert is_nil(spawned.closed_at) and is_nil(spawned.completed_at)
    end

    test "skip requires a note" do
      {scope, obligation} = manager_obligation_scope_fixture()
      assert {:error, _} = Obligations.skip(scope, obligation, %{note: ""})
    end
  end

  describe "end_series/3" do
    test "stamps closed_at + series_ended_at with a series_ended event" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, ended} = Obligations.end_series(scope, obligation, %{note: "stop"})
      assert ended.closed_at
      assert ended.series_ended_at

      events = Obligations.list_events(scope, ended.id)
      assert Enum.any?(events, &(&1.status == "series_ended"))
    end
  end
```

(If `list_events/2` does not exist, fetch events with the project's existing accessor used in other tests — check `test/tugas/obligations_test.exs` for the established pattern and match it.)

- [ ] **Step 8: Run to verify failure**

Run: `mix test test/tugas/obligations_test.exs`
Expected: FAIL — `Obligations.skip/3` undefined; `end_series` still writes `cancelled`/`status`.

- [ ] **Step 9: Implement `skip/3` (replacing `cancel_obligation/3` and `skip_cycle/3`)**

In `lib/tugas/obligations.ex`, delete `cancel_obligation/3`, `skip_cycle/3`, and `skip_cycle_multi/4`. Add:

```elixir
  def skip(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    note = Map.get(attrs, :note) || Map.get(attrs, "note")
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")

    with true <- Authorization.can?(scope, :skip),
         :ok <- validate_action_note(note),
         :ok <- validate_next_due(obligation, attrs) do
      skip_multi(scope, obligation, note, next_due_by)
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  defp skip_multi(scope, obligation, note, next_due_by) do
    now = DateTime.utc_now(:second)
    spawn? = should_spawn_next?(obligation, next_due_by)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :close,
      live(Obligation) |> where([o], o.id == ^obligation.id),
      set: [closed_at: now, updated_at: now]
    )
    |> Ecto.Multi.run(:check, fn _repo, %{close: {count, _}} ->
      if count == 1, do: {:ok, :closed}, else: {:error, :not_live}
    end)
    |> Ecto.Multi.insert(:skipped_event, fn _ ->
      %Event{obligation_id: obligation.id, status_by_id: scope.user.id}
      |> Event.changeset(%{status: "skipped", note: note})
    end)
    |> maybe_spawn_next(spawn?, obligation, next_due_by, scope.user.id)
    |> Repo.transaction()
    |> case do
      {:ok, %{spawn: spawned}} -> {:ok, Repo.get!(Obligation, obligation.id), spawned}
      {:ok, _} -> {:ok, Repo.get!(Obligation, obligation.id), nil}
      {:error, :check, :not_live, _} -> {:error, :not_live}
      {:error, :skipped_event, changeset, _} -> {:error, changeset}
      {:error, :spawn, reason, _} -> {:error, reason}
    end
  end

  defp maybe_spawn_next(multi, false, _obligation, _next_due_by, _actor_id), do: multi

  defp maybe_spawn_next(multi, true, obligation, next_due_by, actor_id) do
    Ecto.Multi.run(multi, :spawn, fn repo, _changes ->
      spawn_next_cycle(repo, obligation, next_due_by, actor_id)
    end)
  end
```

- [ ] **Step 10: Update `end_series/3`**

In `lib/tugas/obligations.ex`, change its multi's `set:` and event status:

```elixir
        set: [closed_at: now, series_ended_at: now, updated_at: now]
```
```elixir
        |> Event.changeset(%{status: "series_ended", note: note})
```

Also rename the multi step `:cancelled_event` → `:series_ended_event` (and its error clause) for clarity. Keep the `live(Obligation) |> where(...)` guard and the `:check` step unchanged.

- [ ] **Step 11: Update `validate_correctable/1` and `locked_cycle?/1`**

Replace the `status`-based clauses (read the current clauses first; preserve the others). Target:

```elixir
  defp validate_correctable(%Obligation{closed_at: %DateTime{}}), do: {:error, :not_correctable}
  defp validate_correctable(%Obligation{completed_at: nil}), do: {:error, :not_correctable}

  defp validate_correctable(%Obligation{completed_in_error_at: %DateTime{}}),
    do: {:error, :already_corrected}

  defp validate_correctable(_), do: :ok
```
```elixir
  defp locked_cycle?(%Obligation{closed_at: %DateTime{}}), do: true
  defp locked_cycle?(%Obligation{completed_at: %DateTime{}}), do: true
  defp locked_cycle?(_), do: false
```

(Match the exact error atoms the current code returns — keep `:not_correctable`/`:already_corrected` as they are today.)

- [ ] **Step 12: Update authorization**

In `lib/tugas/authorization.ex`, replace lines 14-15:

```elixir
  def can?(%Scope{role: :manager}, :skip), do: true
```

(Delete the `:cancel_obligation` and `:skip_cycle` clauses. Admin's `_action -> true` already covers admin.)

- [ ] **Step 13: Update `cycle_status/1`**

In `lib/tugas_web/live/obligation_live/index_helpers.ex`, replace the `cycle_status` clauses:

```elixir
  def cycle_status(%Obligation{completed_at: %DateTime{}}), do: :completed
  def cycle_status(%Obligation{series_ended_at: %DateTime{}}), do: :series_ended
  def cycle_status(%Obligation{closed_at: %DateTime{}}), do: :skipped
  def cycle_status(_), do: :live
```

- [ ] **Step 14: Repoint the show pages' domain calls (keep existing buttons)**

In `lib/tugas_web/live/obligation_live/show.ex` and `lib/tugas_web/live/mobile_live/obligation_show.ex`:
- Replace `Obligations.cancel_obligation(...)` and `Obligations.skip_cycle(...)` calls with `Obligations.skip(...)`.
- The cancel handler passes only `%{note: ...}`; the skip handler passes `%{note: ..., next_due_by: ...}`. Both now return `{:ok, _obligation, _spawned}` — update the cancel handler's match from `{:ok, _}` to `{:ok, _, _}`.
- Replace `Authorization.can?(@current_scope, :cancel_obligation)` and `:skip_cycle` with `:skip`.

Use grep to find every occurrence:

Run: `grep -rn "cancel_obligation\|skip_cycle" lib/tugas_web/`
Update each. (Leave the button labels/modals as-is for now; Task 4 unifies them.)

- [ ] **Step 15: Migrate the IndexHelpers status vocabulary**

In `index_helpers.ex` replace `cancelled` with `skipped` in `@statuses`, `parse_status/1`, `status_label/1`, `empty_message/1`:

```elixir
  @statuses ~w(my_live my_completed live completed skipped all)
  ...
  def parse_status("skipped"), do: :skipped
  ...
  def status_label(:skipped), do: "Skipped"
  ...
  def empty_message(:skipped), do: "No skipped obligations."
```

(Also drop the now-unused `@urgency_rank :ok`? No — leave urgency_rank as is.)

- [ ] **Step 16: Fix fixtures and remaining `status` references**

Run: `grep -rn "status: \"active\"\|status: \"cancelled\"\|\.status\b\|o.status\|:cancelled\|cancel_obligation\|skip_cycle" lib/ test/support/`
Update each: remove `status:` from any fixture `%Obligation{}` build; replace `:cancelled` cycle-status expectations with `:skipped`/`:series_ended` as appropriate.

- [ ] **Step 17: Migrate the broken tests**

Run: `mix test 2>&1 | tail -40` and fix each failure:
- Tests calling `Obligations.cancel_obligation(...)` → `Obligations.skip(...)`, expecting `{:ok, _, nil}`.
- Tests calling `Obligations.skip_cycle(...)` → `Obligations.skip(...)`.
- Assertions on `obligation.status == "cancelled"` → `obligation.closed_at` truthy.
- Assertions on a `cancelled` event → `skipped` (or `series_ended` for end-series).
- `assert_redirect` targets unchanged (already dashboard).

- [ ] **Step 18: Update the authorization test**

In `test/tugas/authorization_test.exs`, replace `:cancel_obligation`/`:skip_cycle` assertions with `:skip` (manager/admin true, member false). Match the file's existing assertion style.

- [ ] **Step 19: Run the full suite**

Run: `mix test`
Expected: PASS (all migrated).

- [ ] **Step 20: precommit + commit**

```bash
mix precommit
git add -A
git commit -m "refactor: status string -> closed_at; unify Cancel+Skip into skip/3"
```

---

### Task 4: Unify the show-page Skip UI (one button + one modal)

**Files:**
- Modify: `lib/tugas_web/live/obligation_live/show.ex`
- Modify: `lib/tugas_web/live/mobile_live/obligation_show.ex`
- Modify: `lib/tugas_web/modal_escape.ex` (if it special-cases the cancel modal)
- Test: `test/tugas_web/live/obligation_live_test.exs`, `test/tugas_web/live/mobile_live_test.exs`

**Interfaces:**
- Consumes: `Obligations.skip/3`, `:skip` authorization.
- Produces: a single `#skip-btn` (desktop) / `#m-skip-btn` (mobile) + one `#skip-modal`/`#skip-form`; the recurring case shows a `next_due_by` field, the one-off case does not.

- [ ] **Step 1: Write the failing test (desktop one-off skip)**

In `test/tugas_web/live/obligation_live_test.exs`:

```elixir
  test "skip modal closes a one-off cycle", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#skip-btn") |> render_click()
    assert has_element?(view, "#skip-modal")

    view
    |> form("#skip-form", %{"skip" => %{"note" => "Not needed"}})
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}")
    assert Obligations.get_obligation!(scope, obligation.id).closed_at
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/tugas_web/live/obligation_live_test.exs -n "skip modal closes a one-off cycle"`
Expected: FAIL — `#skip-btn`/`#skip-modal`/`#skip-form` not found (the page still has Cancel + a recurring-only Skip).

- [ ] **Step 3: Unify the desktop show buttons/modal**

In `lib/tugas_web/live/obligation_live/show.ex`:
- Replace the separate Cancel button (`open_cancel_modal`) and recurring-only Skip button with **one** Skip button shown for every live cycle, gated by `Authorization.can?(@current_scope, :skip)`, `id="skip-btn"`, `phx-click="open_skip_modal"`. Keep the **End series** button (recurring only) as-is.
- Replace the two modals with one `#skip-modal` containing `#skip-form` (`phx-submit="skip"`). Show a `next_due_by` `<.input>` only when `@recurring?` (reuse the Done modal's date-picker markup).
- Handlers: keep `open_skip_modal`/`close`; the `skip` submit handler reads `%{"skip" => params}`, calls `Obligations.skip(@current_scope, @obligation, params)`, matches `{:ok, _, _}` → flash + `push_navigate` to `~p"/entities/#{slug}"`; map `{:error, :next_due_required}` and `{:error, :note_required}`/changeset to a flash. Delete `open_cancel_modal`/`cancel` handlers and the `@show_cancel_modal` assign.
- Update any "· cancelled" / cancelled-summary copy to read off `@cycle_status` (`:skipped` → "skipped", `:series_ended` → "series ended").

- [ ] **Step 4: Mirror on mobile**

Apply the same change in `lib/tugas_web/live/mobile_live/obligation_show.ex` with ids `#m-skip-btn`, `#m-skip-modal`, `#m-skip-form`. The existing mobile `#m-cancel-btn`/`#m-skip-btn` split collapses into the single `#m-skip-btn`.

- [ ] **Step 5: Reconcile ModalEscape**

Run: `grep -n "cancel\|skip" lib/tugas_web/modal_escape.ex`
If `close_obligation_modals/2` clears a `:show_cancel_modal` assign, rename/remove it so it clears `:show_skip_modal`. Keep the single shared closer consistent with the new assign names.

- [ ] **Step 6: Run the targeted + full suite**

Run: `mix test test/tugas_web/live/obligation_live_test.exs test/tugas_web/live/mobile_live_test.exs`
Then fix any mobile test referencing `#m-cancel-btn` (point at `#m-skip-btn`) and any "Cancel"/"cancelled" copy assertions (→ "Skip"/"skipped").
Run: `mix test`
Expected: PASS.

- [ ] **Step 7: precommit + commit**

```bash
mix precommit
git add -A
git commit -m "feat: single Skip action on obligation show (desktop + mobile)"
```

---

### Task 5: Rename the dashboard "Cancelled" filter to "Skipped"

**Files:**
- Modify: `test/tugas_web/live/obligation_live_test.exs`, `test/tugas_web/live/mobile_live_test.exs`
- Verify: `lib/tugas_web/live/dashboard_live/index.ex`, `lib/tugas_web/live/mobile_live/dashboard.ex`, `lib/tugas_web/live/mobile_live/components.ex`

**Interfaces:**
- Consumes: `IndexHelpers` `:skipped` status (Task 3, Step 15) and `cycle_status` (Task 3, Step 13).

- [ ] **Step 1: Update the dashboard filter test**

In `test/tugas_web/live/obligation_live_test.exs`, in the "dashboard filters completed and cancelled cycles" test, change the cancelled section to skipped:

```elixir
    {:ok, skipped} = Obligations.skip(manager, to_cancel, %{note: "No longer needed"})

    view |> element("#filter-skipped") |> render_click()
    assert has_element?(view, "#obligation-row-#{skipped.id}", "Skipped")
```

(Rename the local `to_cancel` setup to a skip; the obligation was created non-recurring so `skip/3` returns `{:ok, skipped, nil}`.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/tugas_web/live/obligation_live_test.exs -n "dashboard filters"`
Expected: FAIL if any mobile/desktop card still emits the old `:cancelled` badge wording.

- [ ] **Step 3: Fix the card meta wording**

In `lib/tugas_web/live/mobile_live/components.ex`, update `card_meta/1` and `accent/1`/`text_color/1` to handle `:skipped` and `:series_ended` (replace the `:cancelled` clause):

```elixir
  defp accent(%{cycle_status: status}) when status in [:skipped, :series_ended],
    do: "border-error/60"

  defp card_meta(%{cycle_status: status, obligation: o}) when status in [:skipped, :series_ended] do
    "#{humanize_cycle(status)} · due #{format_date(o.due_by)}"
  end
```

Add a tiny helper `defp humanize_cycle(:series_ended), do: "series ended"` / `defp humanize_cycle(_), do: "skipped"`. (The `:completed` and live clauses are unchanged.)

- [ ] **Step 4: Update the mobile filter test**

In `test/tugas_web/live/mobile_live_test.exs`, the "mobile dashboard filters completed cycles" test already uses `#m-filter-my_completed`; add/adjust a skipped assertion if present, and ensure no `#m-filter-cancelled` reference remains.

Run: `grep -rn "filter-cancelled\|m-filter-cancelled\|Cancelled" test/tugas_web/live/`
Update each to `skipped`/`Skipped`.

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 6: precommit + commit**

```bash
mix precommit
git add -A
git commit -m "feat: rename dashboard Cancelled filter to Skipped"
```

---

### Task 6: Sync CLAUDE.md and final verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the docs**

In `CLAUDE.md`:
- Roles table: `cancel` / `skip cycle` → a single **skip** (close a cycle; spawns successor when recurring); keep **end series**.
- Obligations domain section: `status` is `active | cancelled` → **removed**; a cycle is **live** while `completed_at IS NULL AND closed_at IS NULL`; Skip stamps `closed_at` + `skipped` event, End series stamps `closed_at`+`series_ended_at` + `series_ended` event; "who" is read from the terminal event (`status_by_id`), no `*_by` columns; completed-in-error remains the column-based exception.
- Event FSM line: `open → in_progress* → done | skipped | series_ended` (singular terminal); mention `Event.terminal_statuses/0`.
- Dashboard/filter section: the `Cancelled` filter is now `Skipped` (= `closed_at IS NOT NULL`).

- [ ] **Step 2: Full verification**

Run: `grep -rn "status ==\|\"cancelled\"\|cancel_obligation\|skip_cycle\|:cancel_obligation\|:skip_cycle" lib/ test/`
Expected: no matches (all retired).
Run: `mix precommit`
Expected: PASS, clean format + warnings-as-errors.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: sync CLAUDE.md with close-model overhaul"
```

---

## Self-Review

**Spec coverage:** §Data model → Task 3 (Steps 1-6); §Event FSM → Task 1; §Domain actions (complete/skip/end_series) → Task 3 (Steps 9-10); §validate_correctable/locked → Task 3 (Step 11); §Authorization → Task 3 (Step 12); §UI badges → Task 2; §show pages → Task 4; §EventMeta → Task 2; §list filter → Task 3 (Step 15) + Task 5; §Testing → folded into each task; §completed-in-error exception → preserved (untouched). All covered.

**Type consistency:** `skip/3` returns `{:ok, Obligation.t(), Obligation.t() | nil}` in Task 3 and is consumed with `{:ok, _, _}` matches in Tasks 3-4; `end_series/3` returns `{:ok, Obligation.t()}`; `:skip` authorization key used in Tasks 3-4; `closed_at`/`series_ended_at`/`completed_at` column names consistent throughout; `cycle_status` values `:completed | :series_ended | :skipped | :live` match the badge clauses in Task 2 and card_meta in Task 5.

**Placeholders:** none — every code step shows full code or an exact grep-and-replace with the target snippet.
