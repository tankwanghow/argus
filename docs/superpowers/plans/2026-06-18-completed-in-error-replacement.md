# Completed-in-Error + Replacement Cycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a manager/admin flag a *completed* obligation cycle as "completed in error" and, in one action, spawn a standalone one-off **replacement** cycle that redoes the work — without uncompleting the wrong cycle or disturbing a recurring series.

**Architecture:** No uncomplete, no event rewrite. The wrong (done) cycle stays immutable; we stamp `completed_in_error_*` columns + an `AuditLog` row on it and link it to a brand-new replacement obligation. The replacement gets its **own new `series_id` with `series_ended_at` pre-set**, which makes it a terminal one-off (`Series.ended?/1` ⇒ no spawn, no `next_due` requirement) even when the type is recurring. A recurring original's auto-spawned successor lives in the *original* series and is therefore untouched.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto 3.13 (binary_id), LiveView 1.2, PostgreSQL.

## Global Constraints

- **binary_id (UUID) PKs everywhere** via `use Tugas.Schema`.
- Contexts take `%Tugas.Accounts.Scope{}` as the first arg; unauthorized mutations return **`:not_authorise`**.
- **Every state transition requires a note** — here the correction `reason` is mandatory (blank ⇒ `{:error, :note_required}`).
- Events are **append-only, forward-only** (`open → in_progress → done | cancelled`). Do **not** add a new event status and do **not** append an event to the wrong cycle.
- The partial unique index `obligations_one_live_cycle_per_series` enforces one live cycle (`status='active' AND completed_at IS NULL`) per `series_id`. The replacement uses a **new** `series_id`, so it never collides.
- `Authorization.can?/2` is the single source of truth for role rules. Manager + admin only.
- Run `mix precommit` before declaring work done.
- Recurrence/interval is read **live from the type**; the replacement is forced to one-off via `series_ended_at`, never by editing the type.

---

### Task 1: Migration + schema fields/associations

**Files:**
- Create: `priv/repo/migrations/20260618120000_add_completed_in_error_to_obligations.exs`
- Modify: `lib/tugas/obligations/obligation.ex` (schema block at lines 9-24)
- Test: `test/tugas/obligations_test.exs` (new test in an existing or new describe block)

**Interfaces:**
- Produces: `Obligation` schema gains fields `completed_in_error_at :utc_datetime`, `completed_in_error_reason :string`, and `belongs_to` assocs `completed_in_error_by` (`completed_in_error_by_id`), `replaces` (`replaces_id`, self-ref), `replaced_by` (`replaced_by_id`, self-ref). All nullable, default nil.

- [ ] **Step 1: Write the failing test**

In `test/tugas/obligations_test.exs`, add inside the top-level module (after the existing `describe "create_obligation/2"` block — reuse `manager_scope_fixture`, `type_fixture` already imported via `Tugas.ObligationsFixtures`):

```elixir
  describe "completed-in-error schema" do
    test "new correction fields default to nil on a created obligation" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      assert obligation.completed_in_error_at == nil
      assert obligation.completed_in_error_by_id == nil
      assert obligation.completed_in_error_reason == nil
      assert obligation.replaces_id == nil
      assert obligation.replaced_by_id == nil
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/obligations_test.exs -k "new correction fields default"`
Expected: FAIL — `KeyError`/unknown field `completed_in_error_at` (schema doesn't define it yet).

- [ ] **Step 3: Write the migration**

Create `priv/repo/migrations/20260618120000_add_completed_in_error_to_obligations.exs`:

```elixir
defmodule Tugas.Repo.Migrations.AddCompletedInErrorToObligations do
  use Ecto.Migration

  def change do
    alter table(:obligations) do
      add :completed_in_error_at, :utc_datetime
      add :completed_in_error_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)
      add :completed_in_error_reason, :string
      add :replaces_id, references(:obligations, type: :binary_id, on_delete: :nilify_all)
      add :replaced_by_id, references(:obligations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:obligations, [:replaces_id])
    create index(:obligations, [:replaced_by_id])
  end
end
```

- [ ] **Step 4: Add fields/associations to the schema**

In `lib/tugas/obligations/obligation.ex`, the schema currently ends:

```elixir
    field :complete_documents, :string, default: ""
    field :open_note, :string, virtual: true

    belongs_to :entity, Entity
    belongs_to :obligation_type, Type
    belongs_to :primary_assignee, User, foreign_key: :primary_assignee_id

    has_many :events, Event
    has_many :collaborators, Collaborator
```

Add the correction fields/assocs right after `field :open_note`:

```elixir
    field :complete_documents, :string, default: ""
    field :open_note, :string, virtual: true

    field :completed_in_error_at, :utc_datetime
    field :completed_in_error_reason, :string

    belongs_to :entity, Entity
    belongs_to :obligation_type, Type
    belongs_to :primary_assignee, User, foreign_key: :primary_assignee_id
    belongs_to :completed_in_error_by, User, foreign_key: :completed_in_error_by_id
    belongs_to :replaces, __MODULE__, foreign_key: :replaces_id
    belongs_to :replaced_by, __MODULE__, foreign_key: :replaced_by_id

    has_many :events, Event
    has_many :collaborators, Collaborator
```

Note: `@cast_fields` is **unchanged** — these columns are set via `put_change` in the context, never user-cast.

- [ ] **Step 5: Migrate the test DB and run the test**

Run: `mix ecto.migrate && mix test test/tugas/obligations_test.exs -k "new correction fields default"`
Expected: PASS. (`mix test` auto-migrates, but run `ecto.migrate` so dev DB is current too.)

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/20260618120000_add_completed_in_error_to_obligations.exs lib/tugas/obligations/obligation.ex test/tugas/obligations_test.exs
git commit -m "feat: add completed-in-error + replacement columns to obligations

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Authorization for `:mark_completed_in_error`

**Files:**
- Modify: `lib/tugas/authorization.ex` (manager clauses, around lines 11-18)
- Test: `test/tugas/authorization_test.exs`

**Interfaces:**
- Produces: `Authorization.can?(scope, :mark_completed_in_error)` ⇒ `true` for `:admin` (existing catch-all) and `:manager` (new clause), `false` for `:member`.

- [ ] **Step 1: Write the failing test**

In `test/tugas/authorization_test.exs`, add (mirror the style of existing role tests in that file — build scopes with the role set; check the file's existing helpers for constructing `%Scope{role: ...}`):

```elixir
  describe "mark_completed_in_error" do
    test "admin and manager may, member may not" do
      assert Tugas.Authorization.can?(%Tugas.Accounts.Scope{role: :admin}, :mark_completed_in_error)
      assert Tugas.Authorization.can?(%Tugas.Accounts.Scope{role: :manager}, :mark_completed_in_error)
      refute Tugas.Authorization.can?(%Tugas.Accounts.Scope{role: :member}, :mark_completed_in_error)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/authorization_test.exs -k "admin and manager may"`
Expected: FAIL — manager assertion fails (`can?/2` manager catch-all returns `false`).

- [ ] **Step 3: Add the manager clause**

In `lib/tugas/authorization.ex`, the manager `can?/2` clauses end with `:void_document` then the catch-all:

```elixir
  def can?(%Scope{role: :manager}, :void_document), do: true
  def can?(%Scope{role: :manager}, _), do: false
```

Insert the new clause **before** the manager catch-all:

```elixir
  def can?(%Scope{role: :manager}, :void_document), do: true
  def can?(%Scope{role: :manager}, :mark_completed_in_error), do: true
  def can?(%Scope{role: :manager}, _), do: false
```

(Admin is already covered by `def can?(%Scope{role: :admin}, _action), do: true`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/tugas/authorization_test.exs -k "admin and manager may"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tugas/authorization.ex test/tugas/authorization_test.exs
git commit -m "feat: authorize mark_completed_in_error for manager and admin

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Context `mark_completed_in_error/3` — flag original + create replacement (non-recurring)

**Files:**
- Modify: `lib/tugas/obligations.ex` (add public fn near `cancel_obligation/3` ~line 589; add private helpers near `spawn_next_cycle` ~line 761 and `validate_*` ~line 1078)
- Test: `test/tugas/obligations_test.exs`

**Interfaces:**
- Consumes: `Authorization.can?/2` (`:mark_completed_in_error`), `validate_action_note/1`, `insert_audit_log!/6`, `Obligation.changeset/2`, `Event.changeset/2`, `Collaborator`, `Repo`.
- Produces:
  ```elixir
  @spec mark_completed_in_error(Scope.t(), Obligation.t(), map()) ::
          {:ok, original :: Obligation.t(), replacement :: Obligation.t()}
          | :not_authorise
          | {:error, :not_correctable | :already_corrected | :note_required | Ecto.Changeset.t()}
  def mark_completed_in_error(scope, obligation, attrs)
  ```
  `attrs` keys (string or atom): `reason` (required, non-blank), `replacement_due_by` (optional `Date`/ISO string; defaults to `obligation.due_by`). The replacement has a fresh `series_id`, `series_ended_at` set (one-off), copies title/type/assignee/collaborators, re-snapshots `complete_documents` from the type, and an `open` event whose note is `reason`. The original gets `completed_in_error_at/by_id/reason` + `replaced_by_id` and an `AuditLog` row (field `"completed_in_error"`).

- [ ] **Step 1: Write the failing test (happy path, non-recurring)**

In `test/tugas/obligations_test.exs`, add a new describe block:

```elixir
  describe "mark_completed_in_error/3" do
    test "flags the done cycle and spawns a standalone one-off replacement" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:ok, original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{reason: "Wrong figures filed"})

      # original flagged, not mutated into a live cycle
      assert original.completed_in_error_at
      assert original.completed_in_error_by_id == manager.user.id
      assert original.completed_in_error_reason == "Wrong figures filed"
      assert original.replaced_by_id == replacement.id
      assert original.completed_at == done.completed_at

      # replacement is a fresh, live, standalone one-off
      assert replacement.series_id != original.series_id
      assert replacement.series_ended_at
      assert replacement.status == "active"
      assert replacement.completed_at == nil
      assert replacement.due_by == ~D[2026-06-15]
      assert replacement.title == "EPF Jan"
      assert replacement.primary_assignee_id == member.user.id
      assert replacement.replaces_id == original.id

      # open event carries the reason
      open_event = Obligations.latest_event(replacement)
      assert open_event.status == "open"
      assert open_event.note == "Wrong figures filed"

      # an audit row was written on the original
      assert Enum.any?(
               Obligations.list_audit_logs(original),
               &(&1.field == "completed_in_error" and &1.new_value == "Wrong figures filed")
             )
    end

    test "replacement_due_by overrides the inherited due date" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:ok, _original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ~D[2026-07-01]
               })

      assert replacement.due_by == ~D[2026-07-01]
    end

    test "completing the one-off replacement does not require next_due and does not spawn" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      # recurring type — but the replacement must still behave as a one-off
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} =
        Obligations.complete(manager, obligation, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "redo"})

      # No next_due required, returns spawned == nil (series already ended on the replacement).
      assert {:ok, completed_replacement, nil} =
               Obligations.complete(manager, replacement, %{note: "Redone"})

      assert completed_replacement.completed_at
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas/obligations_test.exs -k "mark_completed_in_error"`
Expected: FAIL — `UndefinedFunctionError` for `Obligations.mark_completed_in_error/3`.

- [ ] **Step 3: Add the public function**

In `lib/tugas/obligations.ex`, add **after** `cancel_obligation/3` (which ends ~line 589):

```elixir
  @doc """
  Flags a *completed* cycle as completed-in-error and spawns a standalone one-off
  replacement (new `series_id`, `series_ended_at` set so it never spawns). Manager/admin
  only. The wrong cycle is never uncompleted; it is stamped + audited and linked to the
  replacement. Returns `{:ok, original, replacement}`.
  """
  def mark_completed_in_error(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    obligation = Repo.preload(obligation, [:collaborators, :obligation_type])
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason")

    replacement_due_by =
      Map.get(attrs, :replacement_due_by) || Map.get(attrs, "replacement_due_by") ||
        obligation.due_by

    with true <- Authorization.can?(scope, :mark_completed_in_error),
         :ok <- validate_correctable(obligation),
         :ok <- validate_action_note(reason),
         {:ok, original, replacement} <-
           mark_in_error_multi(scope, obligation, reason, replacement_due_by) do
      {:ok, original, replacement}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end
```

- [ ] **Step 4: Add the validation + transaction helpers**

In `lib/tugas/obligations.ex`, add near the other `validate_*` private helpers (e.g. just above `validate_action_note/1` ~line 1078):

```elixir
  defp validate_correctable(%Obligation{status: "cancelled"}), do: {:error, :not_correctable}
  defp validate_correctable(%Obligation{completed_at: nil}), do: {:error, :not_correctable}

  defp validate_correctable(%Obligation{completed_in_error_at: %DateTime{}}),
    do: {:error, :already_corrected}

  defp validate_correctable(%Obligation{}), do: :ok
```

And add the transaction helper near `spawn_next_cycle/4` (~line 761):

```elixir
  defp mark_in_error_multi(scope, obligation, reason, replacement_due_by) do
    type = obligation.obligation_type
    now = DateTime.utc_now(:second)
    series_id = Ecto.UUID.generate()

    replacement_changeset =
      %Obligation{
        entity_id: obligation.entity_id,
        series_id: series_id,
        status: "active",
        series_ended_at: now,
        complete_documents: type.complete_documents
      }
      |> Obligation.changeset(%{
        title: obligation.title,
        obligation_type_id: obligation.obligation_type_id,
        primary_assignee_id: obligation.primary_assignee_id,
        due_by: replacement_due_by
      })
      |> Ecto.Changeset.put_change(:replaces_id, obligation.id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:replacement, replacement_changeset)
    |> Ecto.Multi.insert_all(:collaborators, Collaborator, fn %{replacement: replacement} ->
      Enum.map(obligation.collaborators, fn c ->
        %{
          id: Ecto.UUID.generate(),
          obligation_id: replacement.id,
          user_id: c.user_id,
          inserted_at: now
        }
      end)
    end)
    |> Ecto.Multi.insert(:open_event, fn %{replacement: replacement} ->
      %Event{obligation_id: replacement.id, status_by_id: scope.user.id}
      |> Event.changeset(%{status: "open", note: reason})
    end)
    |> Ecto.Multi.update(:original, fn %{replacement: replacement} ->
      obligation
      |> Obligation.changeset(%{})
      |> Ecto.Changeset.put_change(:completed_in_error_at, now)
      |> Ecto.Changeset.put_change(:completed_in_error_by_id, scope.user.id)
      |> Ecto.Changeset.put_change(:completed_in_error_reason, reason)
      |> Ecto.Changeset.put_change(:replaced_by_id, replacement.id)
    end)
    |> Ecto.Multi.run(:audit, fn repo, _changes ->
      insert_audit_log!(repo, scope, obligation, "completed_in_error", nil, reason)
      {:ok, :logged}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{original: original, replacement: replacement}} ->
        {:ok, original, replacement}

      {:error, _step, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/tugas/obligations_test.exs -k "mark_completed_in_error"`
Expected: PASS (all three tests).

- [ ] **Step 6: Commit**

```bash
git add lib/tugas/obligations.ex test/tugas/obligations_test.exs
git commit -m "feat: mark_completed_in_error flags done cycle and spawns one-off replacement

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Context guards + recurring-series isolation

**Files:**
- Modify: none (logic already in Task 3) — this task only adds tests proving the guards and the recurring isolation.
- Test: `test/tugas/obligations_test.exs` (extend the `mark_completed_in_error/3` describe block)

**Interfaces:**
- Consumes: `Obligations.mark_completed_in_error/3` (from Task 3), `Obligations.list_series/1`, `Obligations.live/1`.

- [ ] **Step 1: Write the failing tests**

Append to the `describe "mark_completed_in_error/3"` block:

```elixir
    test "a recurring original's auto-spawned successor is untouched" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, spawned} =
        Obligations.complete(manager, obligation, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "redo"})

      # The recurring successor still lives, still in the original series, unchanged.
      reloaded = Obligations.get_obligation!(manager, spawned.id)
      assert reloaded.completed_at == nil
      assert reloaded.status == "active"
      assert reloaded.series_id == done.series_id
      assert reloaded.replaces_id == nil

      # The replacement is in its own series, separate from the recurring chain.
      assert replacement.series_id != done.series_id
      assert spawned.id in Enum.map(Obligations.list_series(done.series_id), & &1.id)
      refute replacement.id in Enum.map(Obligations.list_series(done.series_id), & &1.id)
    end

    test "rejects a live (not completed) cycle" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      assert {:error, :not_correctable} =
               Obligations.mark_completed_in_error(manager, obligation, %{reason: "x"})
    end

    test "rejects a cancelled cycle" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, cancelled} = Obligations.cancel_obligation(manager, obligation, %{note: "drop"})

      assert {:error, :not_correctable} =
               Obligations.mark_completed_in_error(manager, cancelled, %{reason: "x"})
    end

    test "rejects double-correction" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})
      {:ok, original, _replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "first"})

      assert {:error, :already_corrected} =
               Obligations.mark_completed_in_error(manager, original, %{reason: "second"})
    end

    test "requires a reason" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:error, :note_required} =
               Obligations.mark_completed_in_error(manager, done, %{reason: ""})
    end

    test "members may not correct" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert :not_authorise =
               Obligations.mark_completed_in_error(member, done, %{reason: "x"})
    end
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `mix test test/tugas/obligations_test.exs -k "mark_completed_in_error"`
Expected: PASS (these new tests are green because Task 3 already implements the behavior). If any fail, fix Task 3's logic rather than the test.

- [ ] **Step 3: Commit**

```bash
git add test/tugas/obligations_test.exs
git commit -m "test: guards and recurring-series isolation for mark_completed_in_error

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Desktop LiveView — action, modal, handler, banners

**Files:**
- Modify: `lib/tugas_web/live/obligation_live/show.ex`
  - mount defaults (~line 581, alongside `assign(:show_completion_modal, false)`)
  - render: add a "Completed in error" banner + a "Mark completed in error" action for completed cycles; add the modal
  - `assign_obligation/2` (~line 1127): add `@correctable?`
  - event handlers: add near `delete_document`/`void_document` handlers
- Test: `test/tugas_web/live/obligation_live_test.exs`

**Interfaces:**
- Consumes: `Obligations.mark_completed_in_error/3`, `Authorization.can?/2`, `@cycle_status` (`:completed`), `@obligation.completed_in_error_at`, `@obligation.replaced_by_id`, `@obligation.replaces_id`.
- Produces: events `"open_correct_modal"`, `"close_correct_modal"`, `"confirm_correct"`; assign `@show_correct_modal`, `@correctable?`; DOM ids `#mark-error-btn`, `#correct-modal`, `#correct-form`, `#completed-in-error-banner`, `#replaces-banner`.

- [ ] **Step 1: Write the failing test**

In `test/tugas_web/live/obligation_live_test.exs`, add:

```elixir
  test "manager marks a completed cycle in error and is taken to the replacement", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "open"
      })

    {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{done.id}")

    assert has_element?(view, "#mark-error-btn")

    view |> element("#mark-error-btn") |> render_click()
    assert has_element?(view, "#correct-modal")

    view
    |> form("#correct-form", %{"correct" => %{"reason" => "Wrong figures"}})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    replacement_id = path |> String.split("/") |> List.last()
    refute replacement_id == done.id

    # Original now shows the completed-in-error banner; replacement shows the replaces banner.
    {:ok, original_view, _} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{done.id}")

    assert has_element?(original_view, "#completed-in-error-banner")
    refute has_element?(original_view, "#mark-error-btn")

    {:ok, replacement_view, _} = live(conn, path)
    assert has_element?(replacement_view, "#replaces-banner")
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/obligation_live_test.exs -k "marks a completed cycle in error"`
Expected: FAIL — `#mark-error-btn` not found.

- [ ] **Step 3: Add mount default + `@correctable?` assign**

In `lib/tugas_web/live/obligation_live/show.ex` mount (the chain of `assign(...)` defaults), add after `|> assign(:show_completion_modal, false)`:

```elixir
     |> assign(:show_completion_modal, false)
     |> assign(:show_correct_modal, false)
```

In `assign_obligation/2`, add a `@correctable?` assign (place alongside the other assigns in that function):

```elixir
    |> assign(
      :correctable?,
      Index.cycle_status(obligation) == :completed and
        is_nil(obligation.completed_in_error_at) and
        Authorization.can?(socket.assigns.current_scope, :mark_completed_in_error)
    )
```

- [ ] **Step 4: Add banners + action button + modal to the render**

In the summary `<section id="obligation-summary" ...>`, **after** the `:if={@live?}` actions `<div id="obligation-actions" ...>` block (it ends right before `</section>` at ~line 175), add the completed-cycle action + banners:

```heex
          <div
            :if={@obligation.completed_in_error_at}
            id="completed-in-error-banner"
            class="mt-3 rounded-box border border-warning/40 bg-warning/10 px-3 py-2 text-sm flex flex-wrap items-center gap-2"
          >
            <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning shrink-0" />
            <span class="font-medium">Completed in error.</span>
            <span class="text-base-content/70">{@obligation.completed_in_error_reason}</span>
            <.link
              :if={@obligation.replaced_by_id}
              navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.replaced_by_id}"}
              class="link link-primary ml-auto"
            >
              View replacement
            </.link>
          </div>

          <div
            :if={@obligation.replaces_id}
            id="replaces-banner"
            class="mt-3 rounded-box border border-base-300 bg-base-200/40 px-3 py-2 text-sm flex flex-wrap items-center gap-2"
          >
            <.icon name="hero-arrow-uturn-left-mini" class="size-4 text-base-content/50 shrink-0" />
            <span class="text-base-content/70">Replacement for a cycle completed in error.</span>
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.replaces_id}"}
              class="link link-primary ml-auto"
            >
              View original
            </.link>
          </div>

          <div :if={@correctable?} class="mt-3 pt-3 border-t border-base-300">
            <button
              id="mark-error-btn"
              type="button"
              phx-click="open_correct_modal"
              class="btn btn-outline btn-warning btn-sm gap-1"
            >
              <.icon name="hero-exclamation-triangle-mini" class="size-3.5" /> Mark completed in error
            </button>
          </div>
```

Then add the modal — place it next to the other modals (e.g. after the completion-documents modal `</div>` block, before the timeline `<section>`):

```heex
      <div :if={@show_correct_modal} id="correct-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark completed in error</h3>
          <p class="text-sm text-base-content/60 mt-1">
            This keeps the completed cycle for audit and creates a fresh one-off replacement
            to redo the work. A recurring series is not affected.
          </p>
          <.form for={%{}} id="correct-form" phx-submit="confirm_correct" class="mt-4 space-y-3">
            <.input
              name="correct[reason]"
              value=""
              type="textarea"
              label="Reason (required)"
              required
            />
            <.input
              name="correct[replacement_due_by]"
              value={Date.to_iso8601(@obligation.due_by)}
              type="date"
              label="Replacement due date"
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_correct_modal">Cancel</button>
              <.button class="btn btn-warning" phx-disable-with="Working…">
                Mark in error &amp; create replacement
              </.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_correct_modal">close</button>
        </form>
      </div>
```

- [ ] **Step 5: Add the event handlers**

In `lib/tugas_web/live/obligation_live/show.ex`, add near the other `handle_event/3` clauses (e.g. after the `void_document` handlers):

```elixir
  def handle_event("open_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, true)}
  end

  def handle_event("close_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, false)}
  end

  def handle_event("confirm_correct", %{"correct" => params}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    attrs = %{
      reason: params["reason"],
      replacement_due_by: params["replacement_due_by"]
    }

    case Obligations.mark_completed_in_error(scope, obligation, attrs) do
      {:ok, _original, replacement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cycle marked in error. Replacement created.")
         |> push_navigate(
           to: ~p"/entities/#{scope.entity.slug}/obligations/#{replacement.id}"
         )}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      {:error, reason} when reason in [:not_correctable, :already_corrected] ->
        {:noreply,
         socket
         |> assign(:show_correct_modal, false)
         |> put_flash(:error, "This cycle can no longer be corrected.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark in error.")}
    end
  end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/tugas_web/live/obligation_live_test.exs -k "marks a completed cycle in error"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/tugas_web/live/obligation_live/show.ex test/tugas_web/live/obligation_live_test.exs
git commit -m "feat: desktop mark-completed-in-error action, modal, and banners

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Mobile LiveView — action, modal, handler, banners

**Files:**
- Modify: `lib/tugas_web/live/mobile_live/obligation_show.ex`
  - mount defaults (~line 466, alongside `assign(:show_completion_modal, false)`)
  - `assign_obligation` (~line 947): add `@correctable?`
  - render: banners + action + modal (`modal-bottom` style)
  - event handlers
- Test: `test/tugas_web/live/mobile_live_test.exs`

**Interfaces:**
- Same context API as Task 5. DOM ids prefixed `m-`: `#m-mark-error-btn`, `#m-correct-modal`, `#m-correct-form`, `#m-completed-in-error-banner`, `#m-replaces-banner`. Redirect target uses the mobile route `~p"/m/#{slug}/obligations/#{id}"`.

- [ ] **Step 1: Write the failing test**

In `test/tugas_web/live/mobile_live_test.exs`, add (match the file's existing setup for logging in + building a manager scope; reuse helpers already imported there):

```elixir
  test "mobile: manager marks a completed cycle in error", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "open"
      })

    {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

    {:ok, view, _html} =
      live(conn, ~p"/m/#{manager.entity.slug}/obligations/#{done.id}")

    assert has_element?(view, "#m-mark-error-btn")

    view |> element("#m-mark-error-btn") |> render_click()
    assert has_element?(view, "#m-correct-modal")

    view
    |> form("#m-correct-form", %{"correct" => %{"reason" => "Wrong figures"}})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/m/#{manager.entity.slug}/obligations/"
    refute path =~ done.id

    {:ok, replacement_view, _} = live(conn, path)
    assert has_element?(replacement_view, "#m-replaces-banner")
  end
```

Confirm `Tugas.Obligations` and `type_fixture` are imported/aliased at the top of `mobile_live_test.exs`; if not, add `alias Tugas.Obligations` and ensure `import Tugas.ObligationsFixtures` is present (mirror `obligation_live_test.exs`).

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/tugas_web/live/mobile_live_test.exs -k "manager marks a completed cycle in error"`
Expected: FAIL — `#m-mark-error-btn` not found.

- [ ] **Step 3: Add mount default + `@correctable?`**

In mount defaults add after `|> assign(:show_completion_modal, false)`:

```elixir
     |> assign(:show_completion_modal, false)
     |> assign(:show_correct_modal, false)
```

In `assign_obligation`, add:

```elixir
    |> assign(
      :correctable?,
      Index.cycle_status(obligation) == :completed and
        is_nil(obligation.completed_in_error_at) and
        Authorization.can?(scope, :mark_completed_in_error)
    )
```

(`Index` is already aliased in this module as `TugasWeb.ObligationLive.IndexHelpers`; confirm and use the existing alias. `scope` is the scope already in scope of `assign_obligation`.)

- [ ] **Step 4: Add banners + action + modal**

After the mobile summary's `:if={@live?}` actions block (mirroring desktop placement, before the timeline section), add:

```heex
          <div
            :if={@obligation.completed_in_error_at}
            id="m-completed-in-error-banner"
            class="mt-3 rounded-box border border-warning/40 bg-warning/10 px-3 py-2 text-sm space-y-1"
          >
            <div class="flex items-center gap-2">
              <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning shrink-0" />
              <span class="font-medium">Completed in error.</span>
            </div>
            <p class="text-base-content/70">{@obligation.completed_in_error_reason}</p>
            <.link
              :if={@obligation.replaced_by_id}
              navigate={~p"/m/#{@current_scope.entity.slug}/obligations/#{@obligation.replaced_by_id}"}
              class="link link-primary"
            >
              View replacement
            </.link>
          </div>

          <div
            :if={@obligation.replaces_id}
            id="m-replaces-banner"
            class="mt-3 rounded-box border border-base-300 bg-base-200/40 px-3 py-2 text-sm space-y-1"
          >
            <p class="text-base-content/70">Replacement for a cycle completed in error.</p>
            <.link
              navigate={~p"/m/#{@current_scope.entity.slug}/obligations/#{@obligation.replaces_id}"}
              class="link link-primary"
            >
              View original
            </.link>
          </div>

          <div :if={@correctable?} class="mt-3">
            <button
              id="m-mark-error-btn"
              type="button"
              phx-click="open_correct_modal"
              class="btn btn-outline btn-warning btn-sm w-full gap-1"
            >
              <.icon name="hero-exclamation-triangle-mini" class="size-3.5" /> Mark completed in error
            </button>
          </div>
```

And the modal (bottom-sheet style, matching the other mobile modals):

```heex
      <div :if={@show_correct_modal} id="m-correct-modal" class="modal modal-bottom modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark completed in error</h3>
          <p class="text-sm text-base-content/60 mt-1">
            Keeps this cycle for audit and creates a one-off replacement to redo the work.
          </p>
          <.form for={%{}} id="m-correct-form" phx-submit="confirm_correct" class="mt-4 space-y-3">
            <.input name="correct[reason]" value="" type="textarea" label="Reason (required)" required />
            <.input
              name="correct[replacement_due_by]"
              value={Date.to_iso8601(@obligation.due_by)}
              type="date"
              label="Replacement due date"
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_correct_modal">Cancel</button>
              <.button class="btn btn-warning" phx-disable-with="Working…">Create replacement</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_correct_modal">close</button>
        </form>
      </div>
```

- [ ] **Step 5: Add the event handlers**

Add near the other mobile `handle_event/3` clauses:

```elixir
  def handle_event("open_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, true)}
  end

  def handle_event("close_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, false)}
  end

  def handle_event("confirm_correct", %{"correct" => params}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    attrs = %{reason: params["reason"], replacement_due_by: params["replacement_due_by"]}

    case Obligations.mark_completed_in_error(scope, obligation, attrs) do
      {:ok, _original, replacement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cycle marked in error. Replacement created.")
         |> push_navigate(to: ~p"/m/#{scope.entity.slug}/obligations/#{replacement.id}")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      {:error, reason} when reason in [:not_correctable, :already_corrected] ->
        {:noreply,
         socket
         |> assign(:show_correct_modal, false)
         |> put_flash(:error, "This cycle can no longer be corrected.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark in error.")}
    end
  end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/tugas_web/live/mobile_live_test.exs -k "manager marks a completed cycle in error"`
Expected: PASS.

- [ ] **Step 7: Run full precommit + commit**

```bash
mix precommit
```
Expected: compiles clean (warnings-as-errors), formatted, all tests pass.

```bash
git add lib/tugas_web/live/mobile_live/obligation_show.ex test/tugas_web/live/mobile_live_test.exs
git commit -m "feat: mobile mark-completed-in-error action, modal, and banners

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **Why `series_ended_at` on the replacement:** `Series.ended?/1` returns true when *any* obligation in the series has `series_ended_at` set. Pre-setting it on the replacement makes `validate_next_due/2` and `should_spawn_next?/2` short-circuit, so completing the replacement neither requires `next_due_by` nor spawns — a true one-off, regardless of the (possibly recurring) type. (Verified against `lib/tugas/obligations.ex` `validate_next_due/2` and `lib/tugas/obligations/series.ex` `ended?/1`.)
- **Why no event on the wrong cycle:** the event FSM is forward-only and the cycle is already `done`. The correction is recorded via columns + `AuditLog`, not a new event — consistent with the spec's "corrections lock after Done" rule (this is an explicit admin/manager escape hatch).
- **`@cast_fields` unchanged:** all five new columns are set with `put_change`, never user-cast, so they can't be tampered with through the obligation form.
- **List/dashboard behavior is unchanged:** the wrong cycle is `completed` (non-live) so it stays in completed filters; the replacement is live and surfaces in My work / Team overview automatically. No list-query changes needed.

## Out of scope (call out, don't build)

- A flag-only correction (mark in error without a replacement) — not requested; current flow always creates the replacement.
- Policy B (cancel the recurring successor) — explicitly deferred; recurrence is left untouched per the chosen Policy A.
- Editing the wrong cycle's note/files in place — intentionally not supported; the replacement is the single source of truth for the redo.
