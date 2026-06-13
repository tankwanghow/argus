# Argus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Argus — a multi-tenant Phoenix LiveView app for tracking obligations with event-based audit trails, recurrence via `series_id`, and dashboard urgency badges.

**Architecture:** Phoenix 1.8 LiveView monolith with PostgreSQL. Multi-tenancy via `entities`
scoped routes — **dual interface**: Desktop `/entities/:entity_slug/...` and Mobile
`/m/:entity_slug/...` (peggy model), auto-routed by `AutoRouteByDevice`. Domain logic in context
modules (`Argus.Obligations`, `Argus.Entities`, `Argus.Accounts`). Request state flows through a
`%Argus.Accounts.Scope{user, entity, membership, role}` as `@current_scope`. Dashboard computes
overdue/due-soon from `due_by` and type `reminder_offsets` — no background jobs. Local filesystem
uploads for v1 documents.

**Conventions:** Follow the sibling Phoenix apps in `~/Projects/elixir` — **peggy** (UI,
magic-link onboarding, scope, Desktop/Mobile) and **full_circle** (contexts, authorization). The
authoritative guide is the **`argus-conventions` skill** (`.claude/skills/argus-conventions.md`);
peggy's `AGENTS.md` ruleset applies. Magic-link-first auth (password fallback), Tailwind v4 + daisyUI 5,
`to_form`/`<.input>`, streams, `<.icon>`; unauthorized context calls return `:not_authorise`.

**Tech Stack:** Elixir 1.19, OTP 28, Phoenix 1.8.5, LiveView 1.2.1, Ecto 3.13, PostgreSQL (citext),
Tailwind v4 + daisyUI 5, Swoosh mailer (magic-link), Req

**Spec:** `docs/superpowers/specs/2026-06-13-argus-design.md`

---

## File map (created incrementally)

```text
lib/argus/
  schema.ex                          # use Argus.Schema — binary_id PKs
  repo.ex
  application.ex
  accounts.ex                        # users, magic-link tokens, registration
  accounts/user.ex
  accounts/user_token.ex
  accounts/scope.ex                  # %Scope{user, entity, membership, role} (peggy)
  entities.ex                        # entities, memberships, invitations
  entities/entity.ex
  entities/membership.ex
  entities/invitation.ex
  obligations.ex                     # public context API
  obligations/type.ex
  obligations/obligation.ex
  obligations/event.ex
  obligations/event_document.ex
  obligations/audit_log.ex
  obligations/recurrence.ex          # next-due calculation
  obligations/completion.ex          # Done validation
  obligations/series.ex              # series_ended?/end_series
  obligations/urgency.ex             # overdue / due_soon badges from reminder_offsets
  authorization.ex                   # can?(scope, action[, obligation])
  uploads.ex                         # local file storage

lib/argus_web/
  router.ex
  user_auth.ex                       # phx.gen.auth: scope plugs + on_mount hooks
  plugs/auto_route_by_device.ex      # Desktop ⇄ Mobile redirect (peggy), argus_view cookie
  plugs/require_role.ex
  components/layouts.ex              # app/1 (desktop navbar) + mobile_app/1 (bottom nav)
  components/core_components.ex      # daisyUI-based inputs, buttons, modal, icon
  components/urgency_badge.ex
  live/user_live/registration.ex     # email-only register → deliver login link
  live/user_live/login.ex
  live/user_live/confirmation.ex     # /users/log-in/:token magic-link confirm
  live/entity_live/select.ex         # pick/create entity after sign-in
  # Desktop UI (/entities/:entity_slug/...)
  live/dashboard_live/index.ex
  live/obligation_live/index.ex
  live/obligation_live/show.ex       # workflow: open → in_progress → done
  live/obligation_live/form.ex
  live/obligation_type_live/index.ex
  live/obligation_type_live/form.ex
  live/membership_live/index.ex
  # Mobile UI (/m/:entity_slug/...) — own LiveViews, mobile_app layout
  live/mobile_live/dashboard.ex
  live/mobile_live/obligations.ex
  live/mobile_live/obligation_show.ex

priv/repo/migrations/              # one migration per table group
priv/repo/seeds.exs                # system obligation type presets
test/argus/                        # context tests (TDD)
test/argus_web/live/               # LiveView tests
```

---

## Task 1: Bootstrap Phoenix project

**Files:**
- Create: entire project via `mix phx.new`

- [ ] **Step 1: Generate app** (keep mailer + assets — magic-link email and daisyUI UI need them)

```bash
cd /home/tankwanghow/Projects/elixir
mix phx.new argus --binary-id --no-dashboard
```

When prompted for `argus` directory already exists (has `docs/`), answer **Y** to continue.

- [ ] **Step 2: Add dependencies**

Modify `mix.exs` deps list — add:

```elixir
{:bcrypt_elixir, "~> 3.0"},   # optional password auth alongside magic-link
{:tzdata, "~> 1.1"}            # entity-timezone urgency
```

Run: `mix deps.get`

- [ ] **Step 3: Wire the shared workspace toolchain** (match every sibling project)

Argus shares the pinned asset binaries under `~/Projects/elixir/.global_assets` via
`~/Projects/elixir/shared_config` — don't let `phx.new` install its own. **Copy peggy's wiring
verbatim, renaming the profile `peggy` → `argus`:**

1. `~/Projects/elixir/.global_assets/setup.sh` — once, to fetch esbuild 0.28.1 / tailwindcss
   4.3.1 / heroicons v2.2.0. Add `argus` to that script's `link_heroicons` project list.
2. `config/config.exs` — prepend the shared-asset import block, name the esbuild/tailwind profiles
   `argus`, and add the time-zone DB (urgency needs real zones):

   ```elixir
   workspace_assets_config = Path.expand("../../shared_config/assets.exs", __DIR__)
   if File.exists?(workspace_assets_config) do
     import_config workspace_assets_config
   else
     config :esbuild, version: "0.28.1"
     config :tailwind, version: "4.3.1"
   end
   # ...
   config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
   ```
3. `mix.exs` — replace the generated heroicons dep with `heroicons_dep()`; add peggy's
   `workspace_assets?/0`, `load_workspace_assets!/0`, `heroicons_dep/0`, `assets_setup_tasks/0`
   (all with the github/hex fallbacks); aliases `"assets.setup": assets_setup_tasks()`,
   `"assets.build": ["compile", "tailwind argus", "esbuild argus"]`, matching `assets.deploy`,
   plus `precommit`.
4. `assets/css/app.css` — keep the stock Phoenix 1.8 daisyUI 5 setup (`@import "tailwindcss"` +
   `@source` + `@plugin "../vendor/{heroicons,daisyui,daisyui-theme}"`); copy peggy's light/dark
   themes. No `tailwind.config.js`, no `@apply`.

Confirm `mix setup` then `mix assets.build` succeed.

- [ ] **Step 4: Verify boot**

Run: `mix test`  
Expected: PASS (0 failures, generated scaffold tests)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: bootstrap Phoenix app (shared toolchain, daisyUI, mailer for magic-link)"
```

---

## Task 2: Base schema and citext extension

**Files:**
- Create: `lib/argus/schema.ex`
- Create: `priv/repo/migrations/20260613000001_enable_extensions.exs`

- [ ] **Step 1: Write Schema module**

```elixir
# lib/argus/schema.ex
defmodule Argus.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
```

- [ ] **Step 2: Migration for extensions**

```elixir
# priv/repo/migrations/20260613000001_enable_extensions.exs
defmodule Argus.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""
  end
end
```

- [ ] **Step 3: Run migration**

Run: `mix ecto.migrate`  
Expected: `enable_extensions` migrated

- [ ] **Step 4: Commit**

```bash
git add lib/argus/schema.ex priv/repo/migrations/
git commit -m "chore: add Argus.Schema and citext extension"
```

---

## Task 3: Users, magic-link auth, and Scope (peggy onboarding)

Argus uses Phoenix 1.8 **`phx.gen.auth` magic-link-first** auth, exactly like peggy — register
with email, get an emailed login link, confirm, sign in — **with email+password as a fallback
login** for users who opt to set one. Generate it rather than hand-rolling; then customize. Mirror
`peggy/lib/peggy_web/live/user_live/*` and `peggy/lib/peggy/accounts/scope.ex`.

**Files:**
- Generate: `mix phx.gen.auth Accounts User users` (creates `accounts.ex`, `accounts/user.ex`,
  `accounts/user_token.ex`, `accounts/scope.ex`, `argus_web/user_auth.ex`,
  `live/user_live/{registration,login,confirmation,settings}.ex`, migration, fixtures)
- Customize: `lib/argus/accounts/user.ex` (add `locale`, citext email), `lib/argus/accounts/scope.ex`
  (add `entity`, `membership`, `role` + `put_entity/3`, `member?/1`)
- Edit: `test/argus/accounts_test.exs`, `test/support/fixtures/accounts_fixtures.ex`

- [ ] **Step 1: Generate auth, accept the magic-link flow**

Run `mix phx.gen.auth Accounts User users`, `mix deps.get`, `mix ecto.migrate`. The generated
flow is email-first: `register_user/1`, `deliver_login_instructions/2`, login-by-token, **plus a
password login form on `UserLive.Login` and password set/change in `UserLive.Settings`**. Keep
**both**: magic-link is the primary/registration path (don't add a password field to
registration), email+password is the fallback. `hashed_password` stays nullable.

- [ ] **Step 2: Write failing tests** for the Argus-specific bits

```elixir
# test/argus/accounts_test.exs (additions)
test "register_user/1 registers with email and defaults locale to en" do
  {:ok, user} = Accounts.register_user(%{email: "a@b.com"})
  assert user.email == "a@b.com"
  assert user.locale == "en"
end

# test/argus/accounts/scope_test.exs
test "put_entity/3 sets entity, membership and role" do
  scope = Scope.for_user(user_fixture())
  scope = Scope.put_entity(scope, entity, %Membership{role: "admin"})
  assert scope.entity == entity
  assert scope.role == :admin
end
```

Run: `mix test` → FAIL (locale/Scope.put_entity not present yet).

- [ ] **Step 3: Customize the generated schema** — add a `locale` column

```bash
mix ecto.gen.migration add_locale_to_users
```

Add `add :locale, :string, null: false, default: "en"` to `users`. (The generator already makes
`email` citext, `hashed_password` **nullable**, `confirmed_at`, and the `users_tokens` table with
`authenticated_at` — leave those.) Cast `:locale` in the User registration changeset; **never**
cast `entity_id`/programmatic fields.

- [ ] **Step 4: Extend `Accounts.Scope`** (mirror peggy)

```elixir
defstruct user: nil, entity: nil, membership: nil, role: nil
def for_user(%User{} = user), do: %__MODULE__{user: user}
def put_entity(%__MODULE__{} = scope, %Entity{} = entity, %Membership{} = m),
  do: %{scope | entity: entity, membership: m, role: String.to_existing_atom(m.role)}
def member?(%__MODULE__{membership: %Membership{accepted_at: %DateTime{}}}), do: true
def member?(_), do: false
```

(`entity`/`membership` are populated later by the entity-scoped `on_mount` in Task 5.)

- [ ] **Step 5: Run tests** → `mix test` PASS

- [ ] **Step 6: Commit**

```bash
git commit -am "feat: magic-link auth (phx.gen.auth) + Scope with locale"
```

---

## Task 4: Entities, memberships, invitations

**Files:**
- Create: `priv/repo/migrations/20260613000003_create_entities.exs`
- Create: `lib/argus/entities/entity.ex`
- Create: `lib/argus/entities/membership.ex`
- Create: `lib/argus/entities/invitation.ex`
- Create: `lib/argus/entities.ex`
- Create: `test/argus/entities_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
test "create_entity/2 creates entity and admin membership" do
  scope = Scope.for_user(user_fixture())        # scope carries only the user pre-selection
  {:ok, entity} = Entities.create_entity(scope, %{slug: "acme", name: "Acme Sdn Bhd"})
  assert entity.slug == "acme"
  membership = Entities.get_membership!(scope.user, entity)
  assert membership.role == "admin"
end
```

- [ ] **Step 2: Migration** — per spec (`entities`, `memberships`, `entity_invitations`); use `binary_id` FKs; partial unique index on `memberships_one_default_per_user`.

- [ ] **Step 3: Implement Entities context**

Key functions:
- `create_entity/2` — insert entity + admin membership
- `list_user_entities/1` — **filters `deleted_at IS NULL`** (soft-deleted entities never appear)
- `get_entity_by_slug_for_user!/2` — slug lookup scoped to the user's memberships **and
  `deleted_at IS NULL`** (used by the entity-scoped `on_mount` in Task 5, so a soft-deleted
  entity's routes become unreachable). Add a test that a soft-deleted entity is not resolved.
- `get_membership!/2`
- `seats_available?/1` — `count(active memberships) < entity.seat_limit`; the **single gate** for
  every path that adds a member
- `invite_member/4` — manager/admin only (authorization added later); rejects when
  `not seats_available?/1` → `{:error, :seat_limit_reached}`
- `accept_invitation/2` — **re-checks `seats_available?/1`** at accept time (seats may have filled
  since the invite) → `{:error, :seat_limit_reached}`. Add a test for the invite-then-fill race.

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: entities, memberships, invitations"
```

---

## Task 5: Entity-scoped `live_session`, dual-UI routing, device auto-route

Replace the standalone "set active entity" plug with peggy's **scope `on_mount`** model. The
`:entity_slug` is resolved in an `on_mount` hook that verifies membership and calls
`Scope.put_entity/3`, so `@current_scope.entity`/`.role` are available in every entity-scoped
LiveView. Mirror `peggy/lib/peggy_web/router.ex` and `auto_route_by_device.ex`.

**Files:**
- Modify: `lib/argus_web/user_auth.ex` (add `on_mount(:require_entity, ...)`)
- Modify: `lib/argus_web/router.ex`
- Create: `lib/argus_web/plugs/auto_route_by_device.ex`
- Create: `lib/argus_web/device.ex` (UA sniff helper)
- Create: `test/argus_web/user_auth_test.exs` (entity on_mount), `.../auto_route_by_device_test.exs`

- [ ] **Step 1: `on_mount(:require_entity, ...)`** in `UserAuth`

Reads `params["entity_slug"]`, loads the entity scoped to the user's memberships
(`Entities.get_entity_by_slug_for_user!/2`) + membership, and assigns
`current_scope = Scope.put_entity(socket.assigns.current_scope, entity, membership)`. Halts
(redirect to `/entities`) if the user is not a member.

- [ ] **Step 2: `AutoRouteByDevice` plug** (peggy) in the authed browser pipeline

Redirects `/entities/<slug>/…` → `/m/<slug>/…` for mobile UAs and back for desktop, honoring an
`argus_view=mobile|desktop` cookie set by explicit toggle links. Only redirects when the
counterpart route exists (whitelist of mobile-capable tails) so single-UI pages never 404.

**Mobile scope is decided (not full parity):** mobile covers the field-work surface only —
dashboard, obligation list, and obligation show/workflow (Task 21). **Management flows
(obligation create/edit, type management, members/settings) are Desktop-only by design.** The
`mobile_capable_tails` whitelist therefore lists exactly the three mobile tails (`""`,
`"obligations"`, `"obligations/<id>"`); a mobile UA on a desktop-only path (e.g.
`/entities/:slug/obligations/new`, `/obligation-types`, `/members`) is **not** redirected to a
non-existent `/m/...` route — it renders the desktop LiveView (which the "More" sheet's Desktop
toggle reaches). Add a test asserting a desktop-only tail is absent from the whitelist and is not
redirected for a mobile UA.

- [ ] **Step 3: Router — auth, desktop, and mobile scopes**

```elixir
# with-or-without auth (registration, login, confirmation) — peggy phx.gen.auth blocks
live_session :current_user, on_mount: [{ArgusWeb.UserAuth, :mount_current_scope}] do
  # users/register, users/log-in, users/log-in/:token
end

scope "/", ArgusWeb do
  pipe_through [:browser, :require_authenticated_user, ArgusWeb.Plugs.AutoRouteByDevice]

  live_session :require_authenticated_user,
    on_mount: [{ArgusWeb.UserAuth, :require_authenticated}] do
    live "/entities", EntityLive.Select, :index            # pick/create entity
  end

  live_session :entity_scoped,
    on_mount: [{ArgusWeb.UserAuth, :require_authenticated}, {ArgusWeb.UserAuth, :require_entity}] do
    # Desktop UI
    live "/entities/:entity_slug", DashboardLive.Index, :index
    live "/entities/:entity_slug/obligations", ObligationLive.Index, :index
    live "/entities/:entity_slug/obligations/new", ObligationLive.Form, :new
    live "/entities/:entity_slug/obligations/:id", ObligationLive.Show, :show
    live "/entities/:entity_slug/obligation-types", ObligationTypeLive.Index, :index
    live "/entities/:entity_slug/members", MembershipLive.Index, :index
    # Mobile UI (own LiveViews, mobile_app layout)
    live "/m/:entity_slug", MobileLive.Dashboard, :show
    live "/m/:entity_slug/obligations", MobileLive.Obligations, :index
    live "/m/:entity_slug/obligations/:id", MobileLive.ObligationShow, :show
  end
end
```

State in the implementation which `live_session`/pipeline each route uses and why (peggy rule).

- [ ] **Step 4: `EntityLive.Select`** at `/entities` — list memberships, create-entity form; first
  entity becomes the user's default. Redirects straight in if the user has exactly one entity.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: scope on_mount, dual-UI routing, device auto-route"
```

---

## Task 6: Authorization module

**Files:**
- Create: `lib/argus/authorization.ex`
- Create: `test/argus/authorization_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
test "manager can create obligation" do
  scope = manager_scope_fixture()                  # %Scope{entity, role: :manager, ...}
  assert Authorization.can?(scope, :create_obligation)
end

test "member cannot cancel obligation" do
  scope = member_scope_fixture()
  refute Authorization.can?(scope, :cancel_obligation)
end

test "collaborator cannot mark done" do
  {scope, obligation} = collaborator_scope_fixture()
  refute Authorization.can?(scope, :mark_done, obligation)
end
```

- [ ] **Step 2: Implement `can?/2` and `can?/3`** (scope-first, per `argus-conventions`)

Signatures: `can?(%Scope{}, action)` for entity-level actions and `can?(%Scope{}, action,
%Obligation{})` for obligation-scoped ones. The scope already carries `entity`, `role`, and
`user` (resolved by the `on_mount`), so authorization never re-queries the DB for the role —
unlike full_circle, which re-fetches on every call. Pattern-match on `scope.role` with an
`allow_roles(scope, ~w(admin manager)a)` helper.

Actions: `:manage_entity`, `:manage_types`, `:create_obligation`, `:edit_obligation`, `:mark_done`, `:cancel_obligation`, `:end_series`, `:void_document`, `:start_progress`

Rules per spec (keyed off `scope.role`):
- admin → all
- manager → create, edit, mark_done (any), cancel, end_series
- member → start_progress if primary or collaborator; mark_done if primary only (the 3-arity
  clause compares `obligation.primary_assignee_id`/collaborators against `scope.user.id`)

- [ ] **Step 3: Run tests — PASS**

- [ ] **Step 4: Commit**

---

## Task 7: Obligation types schema and recurrence helper

**Files:**
- Create: `priv/repo/migrations/20260613000004_create_obligation_types.exs`
- Create: `lib/argus/obligations/type.ex`
- Create: `lib/argus/obligations/recurrence.ex`
- Create: `test/argus/obligations/recurrence_test.exs`

- [ ] **Step 1: Write failing recurrence tests**

```elixir
defmodule Argus.Obligations.RecurrenceTest do
  use ExUnit.Case, async: true
  alias Argus.Obligations.Recurrence
  alias Argus.Obligations.Type

  test "next_due_suggestion monthly adds one month" do
    type = %Type{recurring_interval: "monthly"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == ~D[2026-02-15]
  end

  test "custom interval returns nil" do
    type = %Type{recurring_interval: "custom"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == nil
  end

  test "none interval returns nil" do
    type = %Type{recurring_interval: "none"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == nil
  end

  test "none is not recurring" do
    type = %Type{recurring_interval: "none"}
    refute Recurrence.recurring?(type)
  end
end
```

- [ ] **Step 2: Implement Recurrence**

```elixir
defmodule Argus.Obligations.Recurrence do
  alias Argus.Obligations.Type

  @intervals ~w(none weekly every_two_weeks monthly quarterly semiannual annual custom)

  def intervals, do: @intervals

  def recurring?(%Type{recurring_interval: "none"}), do: false
  def recurring?(%Type{}), do: true

  def next_due_suggestion(%Type{recurring_interval: "none"}, _due_by), do: nil
  def next_due_suggestion(%Type{recurring_interval: "custom"}, _due_by), do: nil
  def next_due_suggestion(%Type{recurring_interval: interval}, due_by) do
    case interval do
      "weekly" -> Date.add(due_by, 7)
      "every_two_weeks" -> Date.add(due_by, 14)
      "monthly" -> shift_month(due_by, 1)
      "quarterly" -> shift_month(due_by, 3)
      "semiannual" -> shift_month(due_by, 6)
      "annual" -> shift_month(due_by, 12)
      _ -> nil
    end
  end

  defp shift_month(date, n) do
    # use `:calendar` or Timex-free logic; clamp day to end of month
    %{date | month: date.month + n}  # replace with proper month-add helper in impl
  end
end
```

Implement `shift_month/2` properly (handle Jan 31 + 1 month → Feb 28).

- [ ] **Step 3: Migration for obligation_types**

Fields per spec. `entity_id` nullable for system presets.

- [ ] **Step 4: Type changeset validates interval in `@intervals` and the CSV-in-string fields**

`reminder_offsets` and `complete_documents` are stored as comma-delimited strings but are parsed
on the **dashboard render path** — a malformed value would raise and take down the whole
entity's dashboard. Validate and normalize them at **write time** so render-time parsing can
never fail:

- `reminder_offsets` — each comma-separated token must parse to a **non-negative integer**;
  reject otherwise with a changeset error. Normalize: trim, drop blanks, dedup, sort; store
  canonical `"30,7,1"`. Add a test for a bad value (`"7, ,abc"`) producing an invalid changeset.
- `complete_documents` — trim each slot name, drop blanks, dedup; reject duplicate or empty slot
  names. Store canonical form.

Add a failing changeset test for each before implementing.

- [ ] **Step 5: Run tests — PASS**

- [ ] **Step 6: Commit**

---

## Task 8: Obligations, events, collaborators

**Files:**
- Create: `priv/repo/migrations/20260613000005_create_obligations.exs`
- Create: `lib/argus/obligations/obligation.ex`
- Create: `lib/argus/obligations/event.ex`
- Create: `lib/argus/obligations.ex` (partial — create only)
- Create: `test/argus/obligations_test.exs`
- Create: `test/support/fixtures/obligations_fixtures.ex`

> **Fixture caveat (carries through Tasks 9–12, 14):** `obligation_fixture/*` and
> `recurring_obligation_fixture/*` must build their `ObligationType` with
> `complete_note_required: false` and `complete_documents: ""` (no required slots) **by default** —
> these values are snapshotted onto the obligation at creation, so the obligation inherits "no
> requirements." Otherwise the Task 9 `complete/3` tests for `next_due_required`, idempotency
> (`not_live`), and plain spawn would fail on the note/document validations *before* reaching the
> behavior under test. Tests that specifically exercise completion rules should opt **in** via
> fixture options (e.g. `type_fixture(entity, complete_note_required: true)`), not rely on the
> default. Fixtures return a `%Scope{}` for the actor (e.g. `manager_scope_fixture/0`,
> `assigned_member_scope_fixture/0`) so context calls match the scope-first signatures.

- [ ] **Step 1: Write failing create test**

```elixir
test "create_obligation/2 creates obligation, open event, snapshots type rules, and optional open note" do
  scope = manager_scope_fixture()                       # %Scope{entity, role: :manager, user}
  type = type_fixture(scope.entity, complete_note_required: true, complete_documents: "receipt")
  assignee = member_fixture(scope.entity)

  attrs = %{
    title: "EPF Jan",
    obligation_type_id: type.id,
    primary_assignee_id: assignee.id,
    due_by: ~D[2026-01-15],
    open_note: "Submit by 15th"
  }

  {:ok, obligation} = Obligations.create_obligation(scope, attrs)
  assert obligation.series_id
  assert obligation.status == "active"
  # completion rules are SNAPSHOTTED from the type at creation (a later type edit must not move
  # the bar for this live cycle)
  assert obligation.complete_note_required == true
  assert obligation.complete_documents == "receipt"

  events = Obligations.list_events(obligation)
  assert hd(events).status == "open"
  assert hd(events).note == "Submit by 15th"
end
```

- [ ] **Step 2: Migration**

Tables: `obligations`, `obligation_collaborators`, `obligation_events`.

`obligations` columns include `completed_at :utc_datetime` (nullable), `series_ended_at
:utc_datetime` (nullable), and the **snapshotted completion rules** copied from the type at
creation: `complete_note_required :boolean` and `complete_documents :string`.

Use `due_by` as `:date`. Index `(entity_id, status)`, `(series_id)`, `(primary_assignee_id)`.

**Enforce one live cycle per series** with a partial unique index (a live cycle is
`status = 'active' AND completed_at IS NULL`):

```elixir
create unique_index(:obligations, [:series_id],
  where: "status = 'active' AND completed_at IS NULL",
  name: :obligations_one_live_cycle_per_series)
```

This is what makes concurrent Done calls safe — the second spawn of the same series hits the index and fails.

**Support `Series.ended?/1`** with a partial index so the "is this series ended?" existence check
never scans the chain:

```elixir
create index(:obligations, [:series_id],
  where: "series_ended_at IS NOT NULL",
  name: :obligations_series_ended)
```

- [ ] **Step 2b: Define `Obligations.live/1` — the single live-cycle query**

The live-cycle predicate (`status = "active" AND completed_at IS NULL`) is the most error-prone
query in the app; define it **once** as a composable builder and route every list/dashboard/report
through it — never hand-write the predicate at a call site:

```elixir
import Ecto.Query
def live(query \\ Obligation), do: from(o in query, where: o.status == "active" and is_nil(o.completed_at))
```

- [ ] **Step 3: Implement `create_obligation/2` in transaction** (`create_obligation(scope, attrs)`)

1. Authorize: `Authorization.can?(scope, :create_obligation)` else `:not_authorise`
2. Generate a **new** `series_id` with `Ecto.UUID.generate()` — `create_obligation/2` always starts
   a fresh series. (Continuing an existing series is `spawn_next_cycle/2`, Task 9 — never this path.)
3. Insert obligation — set `entity_id` from `scope.entity` (never from attrs/cast), and
   **snapshot** `complete_note_required` + `complete_documents` from the chosen `ObligationType`
   onto the obligation row (so later type edits don't move the bar for this cycle)
4. Insert collaborators if provided
5. Insert open event with optional `note` (from `open_note` attr), `status_by_id: scope.user.id`

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

---

## Task 9: Workflow transitions (in_progress, done, spawn next)

**Files:**
- Create: `lib/argus/obligations/completion.ex`
- Modify: `lib/argus/obligations.ex`
- Modify: `test/argus/obligations_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
test "start_progress/2 creates in_progress event" do
  {scope, obligation} = assigned_member_scope_fixture()
  {:ok, event} = Obligations.start_progress(scope, obligation)
  assert event.status == "in_progress"
end

test "start_progress/2 is idempotent — rejected if already in_progress or terminal" do
  {scope, obligation} = assigned_member_scope_fixture()
  {:ok, _} = Obligations.start_progress(scope, obligation)
  # latest event is already in_progress → no duplicate forward step
  assert {:error, :not_open} = Obligations.start_progress(scope, obligation)
end

test "complete/3 marks done, stamps completed_at, and spawns next when recurring" do
  {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
  {:ok, done_obligation, new_obligation} =
    Obligations.complete(scope, obligation, %{next_due_by: ~D[2026-02-15]})

  assert done_obligation.completed_at                     # terminal marker set
  assert done_event = Obligations.latest_event(done_obligation)
  assert done_event.status == "done"
  assert new_obligation.due_by == ~D[2026-02-15]
  assert new_obligation.series_id == obligation.series_id
end

test "complete/3 requires next_due_by for a recurring, not-ended series" do
  {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
  # Omitting next_due_by would leave the series with no successor cycle → rejected
  assert {:error, :next_due_required} = Obligations.complete(scope, obligation, %{})
end

test "complete/3 is idempotent — a second Done on the same cycle is rejected" do
  {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
  {:ok, done_obligation, _} =
    Obligations.complete(scope, obligation, %{next_due_by: ~D[2026-02-15]})
  # The cycle is no longer live (completed_at set) — re-completing fails
  assert {:error, :not_live} = Obligations.complete(scope, done_obligation, %{next_due_by: ~D[2026-03-15]})
end

test "end_series cancels the current cycle, so it can never be completed/spawn" do
  {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
  {:ok, ended} = Obligations.end_series(scope, obligation, %{})
  # End series == cancel current obligation + stamp series_ended_at (semantics A)
  assert ended.status == "cancelled"
  assert ended.series_ended_at
  # A non-live (cancelled) cycle cannot be completed — no next obligation is ever spawned
  assert {:error, :not_live} = Obligations.complete(scope, ended, %{})
end
```

- [ ] **Step 2: Implement Completion validation**

Validation reads the **obligation's snapshotted rules** (`obligation.complete_note_required` /
`obligation.complete_documents`), **never the live type** — so a type edited mid-cycle can't
change this cycle's bar (fix #13). `cycle_documents` is **every non-voided
`ObligationEventDocument` across all events in the cycle** (open / in_progress / done), not just
Done-event uploads — so incremental uploads count (fix #6).

```elixir
defmodule Argus.Obligations.Completion do
  alias Argus.Obligations.Obligation

  # `obligation` carries the snapshot; `cycle_documents` spans all events in the cycle.
  def validate_done_requirements(%Obligation{} = obligation, done_attrs, cycle_documents) do
    with :ok <- validate_note(obligation, done_attrs[:note]),
         :ok <- validate_document_slots(obligation, cycle_documents) do
      :ok
    end
  end

  defp validate_note(%Obligation{complete_note_required: true}, note) when note in [nil, ""],
    do: {:error, :note_required}

  defp validate_note(_, _), do: :ok

  defp validate_document_slots(%Obligation{complete_documents: complete_documents}, cycle_documents) do
    required = complete_documents |> parse_csv()
    slots = cycle_documents |> Enum.reject(& &1.voided_at) |> Map.new(&{&1.document_slot, true})

    case Enum.find(required, &(not Map.has_key?(slots, &1))) do
      nil -> :ok
      missing -> {:error, {:missing_document, missing}}
    end
  end
end
```

- [ ] **Step 3: Implement `complete/3`** (`complete(scope, obligation, attrs)`)

In `Ecto.Multi`:
1. Validate authorization (`Authorization.can?(scope, :mark_done, obligation)`) else `:not_authorise`
2. Validate completion requirements against the **obligation snapshot** + **all non-voided
   documents across the cycle's events** (`Completion.validate_done_requirements/3`)
3. **Recurrence guard:** if `Recurrence.recurring?(type)` and not `Series.ended?(series_id)` → `next_due_by` is **required**; missing/blank → `{:error, :next_due_required}`. (This guarantees no series ever loses its successor cycle — fix 5.)
4. **Guarded close (concurrency + idempotency):** stamp `completed_at` with a conditional update —
   `Obligation |> Obligations.live() |> where([o], o.id == ^id) |> Repo.update_all(set: [completed_at: now])`.
   If `0` rows are updated, abort the Multi with `{:error, :not_live}` (someone already
   completed/cancelled it). This is the single source of truth for "is this cycle still live",
   replacing any in-memory `status` check.
5. Insert `done` event (`status_by_id: scope.user.id`) + any Done document
6. If recurring and not ended → call the **private** `spawn_next_cycle/2` (below). **Do not reuse
   `create_obligation/2`** — that function always mints a *new* `series_id` and runs the
   user-facing create path (authorize-as-create, open-note handling); the spawn is a system
   action that must carry the *existing* `series_id`. Overloading one function for both is exactly
   the API ambiguity to avoid.

Return `{:ok, completed, new_obligation | nil}`

- [ ] **Step 3b: Implement private `spawn_next_cycle(done_obligation, next_due_by)`** (called only
  from inside the `complete/3` Multi):

  1. Build a new `Obligation` carrying the **same `series_id`** as `done_obligation`, copying
     `entity_id`, `obligation_type_id`, `title`, and `primary_assignee_id`.
  2. **Re-snapshot** `complete_note_required`/`complete_documents` from the *current* type (a type
     edit takes effect on the next cycle — see the snapshot-vs-live note in Task 8) and set the new
     `due_by` to `next_due_by`.
  3. Copy the `obligation_collaborators` rows.
  4. Insert with `unique_constraint(:series_id, name: :obligations_one_live_cycle_per_series)`;
     translate a constraint failure to `{:error, :not_live}` so a lost spawn race surfaces as a
     clean domain error, never a raw `Ecto` exception (fix #8).
  5. Insert the new cycle's `open` event.

  `create_obligation/2` mints a fresh `series_id` and is the **only** entry point that starts a new
  series; `spawn_next_cycle/2` is the **only** one that continues an existing series.

- [ ] **Step 4: Implement `start_progress/2`** (`start_progress(scope, obligation)`) — authorize
  `:start_progress` (primary or collaborator), then **guard against duplicate forward steps**:
  only insert an `in_progress` event when the cycle is live **and** its latest event status is
  `open`; if the latest event is already `in_progress` or terminal (`done`/`cancelled`), return
  `{:error, :not_open}`. Keeps the append-only log strictly one-step-forward under double-clicks.

- [ ] **Step 5: Implement `Series.ended?/1`** — `Repo.exists?` where `series_id` and `series_ended_at` not nil (backed by the `obligations_series_ended` partial index). Under semantics A, End series cancels the current cycle, so a *live* obligation in an ended series can't exist — this guard is defensive only.

- [ ] **Step 6: Run tests — PASS**

- [ ] **Step 7: Commit**

---

## Task 10: Cancel and end series

**Files:**
- Modify: `lib/argus/obligations.ex`
- Modify: `test/argus/obligations_test.exs`

- [ ] **Step 1: Tests**

```elixir
test "cancel_obligation/3 sets status cancelled and logs event" do
  {scope, obligation} = manager_obligation_scope_fixture()
  {:ok, cancelled} = Obligations.cancel_obligation(scope, obligation, %{})
  assert cancelled.status == "cancelled"
end

test "end_series cancels current obligation and sets series_ended_at" do
  {scope, obligation} = recurring_manager_scope_fixture()
  {:ok, ended} = Obligations.end_series(scope, obligation, %{})
  assert ended.status == "cancelled"
  assert ended.series_ended_at
end
```

- [ ] **Step 2: Implement** (`cancel_obligation(scope, obligation, attrs)` /
  `end_series(scope, obligation, attrs)`) — authorize `:cancel_obligation` / `:end_series`
  (manager/admin) else `:not_authorise`; insert `cancelled` event (`status_by_id: scope.user.id`)
  and set `status: "cancelled"`. `end_series` does the same **plus** sets `series_ended_at` on the
  current (now-cancelled) obligation row (semantics A — authoritative per spec).

- [ ] **Step 3: Run tests — PASS**

- [ ] **Step 4: Commit**

---

## Task 11: Event documents and uploads

**Files:**
- Create: `priv/repo/migrations/20260613000006_create_obligation_event_documents.exs`
- Create: `lib/argus/obligations/event_document.ex`
- Create: `lib/argus/uploads.ex`
- Modify: `lib/argus/obligations.ex`

- [ ] **Step 1: Migration** for `obligation_event_documents` per spec (void fields included). The
  per-file column is **`file`** (a map `%{filename, original, path}`), **not `documents`** — one
  row is one document, and `documents` collides with the type's `complete_documents` slot list.

- [ ] **Step 2: Uploads module** — store under a **configurable base dir**, not a hardcoded
  `priv/` path. `:code.priv_dir` is not writable/persistent inside a release, so the destination
  comes from `config :argus, :uploads_dir` (defaults to the priv path in dev; a persistent volume
  in prod). Save the file map in the DB `file` column.

```elixir
defp base_dir, do: Application.get_env(:argus, :uploads_dir, Path.join(:code.priv_dir(:argus), "uploads"))

def store(%Plug.Upload{} = upload, entity_id, obligation_id) do
  dest_dir = Path.join([base_dir(), entity_id, obligation_id])
  File.mkdir_p!(dest_dir)
  filename = "#{Ecto.UUID.generate()}_#{upload.filename}"
  dest = Path.join(dest_dir, filename)
  File.cp!(upload.path, dest)
  %{filename: filename, original: upload.filename, path: dest}
end
```

- [ ] **Step 3: `add_document/5` and `void_document/4`** (scope-first) with authorization rules.
  `document_slot` is nullable in general, but the upload UI (Tasks 16/21) **requires** a slot when
  the obligation's snapshot lists `complete_documents`, so required-slot files are never orphaned
  (see #10).

- [ ] **Step 4: Scope-gated serving** — a controller/plug streams a stored file **only** after
  verifying the requester's scope/membership owns the obligation's entity. Never expose uploads
  via a static route.

- [ ] **Step 5: Tests for void excluding from completion validation**

- [ ] **Step 6: Commit**

---

## Task 12: Audit log and corrections

**Files:**
- Create: `priv/repo/migrations/20260613000007_create_obligation_audit_logs.exs`
- Create: `lib/argus/obligations/audit_log.ex`
- Modify: `lib/argus/obligations.ex`
- Create: `test/argus/obligations/audit_test.exs`

- [ ] **Step 1: Tests**

```elixir
test "update_obligation/3 logs title change" do
  {scope, obligation} = manager_obligation_scope_fixture()
  {:ok, _updated} = Obligations.update_obligation(scope, obligation, %{title: "New"})
  logs = Obligations.list_audit_logs(obligation)
  assert Enum.any?(logs, &(&1.field == "title"))
end

test "update_obligation/3 logs due_by and primary_assignee changes" do
  {scope, obligation} = manager_obligation_scope_fixture()
  new_assignee = member_fixture(scope.entity)
  {:ok, _} =
    Obligations.update_obligation(scope, obligation, %{
      due_by: ~D[2026-03-01],
      primary_assignee_id: new_assignee.id
    })
  fields = Obligations.list_audit_logs(obligation) |> Enum.map(& &1.field)
  assert "due_by" in fields
  assert "primary_assignee" in fields
end

test "update_collaborators/3 adds and removes, logging each change" do
  {scope, obligation} = manager_obligation_scope_fixture()
  collab = member_fixture(scope.entity)
  {:ok, _} = Obligations.update_collaborators(scope, obligation, [collab.id])
  {:ok, _} = Obligations.update_collaborators(scope, obligation, [])
  fields = Obligations.list_audit_logs(obligation) |> Enum.map(& &1.field)
  assert "collaborators" in fields                       # add + remove both audited
end

test "member cannot update obligation fields" do
  {scope, obligation} = assigned_member_scope_fixture()
  assert :not_authorise = Obligations.update_obligation(scope, obligation, %{title: "X"})
end
```

- [ ] **Step 2: Implement `update_obligation/3`** (`update_obligation(scope, obligation, attrs)`) —
  only **live** obligations; manager/admin (`:edit_obligation` else `:not_authorise`). Editable
  fields per spec: `title`, `due_by`, `primary_assignee_id`. **Log every changed field** to
  `AuditLog` (`old_value`/`new_value`); the assignee change logs under field `primary_assignee`
  (store the user reference, not a raw UUID, for a readable trail).

- [ ] **Step 2b: Implement `update_collaborators/3`** (`update_collaborators(scope, obligation,
  user_ids)`) — manager/admin, live cycles only; diff against current `obligation_collaborators`,
  insert/delete the difference in one transaction, and log additions and removals under field
  `collaborators`. (Collaborators are a join table, not an obligation column, so they need their
  own path — `update_obligation/3` does not touch them.)

- [ ] **Step 3: `edit_note/3`** (`edit_note(scope, event, attrs)`) — author may edit own note
  within a **48-hour window measured on the event's UTC `inserted_at`** (`DateTime.diff/2` ≤
  48*3600 — elapsed wall-clock, no timezone involved); manager/admin override anytime before
  Done; log change. Add a test for the window boundary (e.g. an event `inserted_at` 49h ago is
  locked for its author).

- [ ] **Step 4: Commit**

---

## Task 13: System obligation type seeds

**Files:**
- Modify: `priv/repo/seeds.exs`

- [ ] **Step 1: Seed Malaysia presets** (`entity_id: nil`)

Examples:
- EPF Monthly — `monthly`, `complete_documents: "payment_receipt"`
- SOCSO Monthly — `monthly`
- SST Return — `quarterly`
- SSM Annual Return — `annual`
- LHDN Tax Estimation — `custom`

- [ ] **Step 2: `mix run priv/repo/seeds.exs` — no errors**

- [ ] **Step 3: Commit**

---

## Task 14: Urgency badges (replaces notifications)

**Files:**
- Create: `lib/argus/obligations/urgency.ex`
- Create: `lib/argus_web/components/urgency_badge.ex`
- Create: `test/argus/obligations/urgency_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule Argus.Obligations.UrgencyTest do
  use ExUnit.Case, async: true
  alias Argus.Obligations.Urgency
  alias Argus.Obligations.Type

  @today ~D[2026-06-13]

  test "overdue when due_by is in the past" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-06-10], @today) == :overdue
  end

  test "due_soon when within reminder offset" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-06-18], @today) == :due_soon
  end

  test "ok when outside reminder offsets" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-07-01], @today) == :ok
  end

  # Decided boundary (spec): due *today* is amber (due_soon), NOT red (overdue);
  # overdue means strictly past the deadline.
  test "due today is due_soon, not overdue" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, @today, @today) == :due_soon
  end
end
```

- [ ] **Step 2: Implement Urgency**

```elixir
defmodule Argus.Obligations.Urgency do
  alias Argus.Obligations.Type

  @type urgency :: :overdue | :due_soon | :ok

  # `today` is REQUIRED — callers pass the date in the entity's timezone (see today_for/1).
  # No UTC default: defaulting to Date.utc_today() silently mis-dates non-UTC tenants.
  @spec classify(Type.t(), Date.t(), Date.t()) :: urgency()
  def classify(%Type{reminder_offsets: offsets}, due_by, today) do
    cond do
      Date.compare(due_by, today) == :lt -> :overdue
      due_soon?(offsets, due_by, today) -> :due_soon
      true -> :ok
    end
  end

  # "Today" in the entity's timezone — fix 3. Dashboards compute this once and pass it in.
  @spec today_for(String.t()) :: Date.t()
  def today_for(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()            # fall back only if the tz is unknown to tzdata
    end
  end

  defp due_soon?(offsets, due_by, today) do
    days = Date.diff(due_by, today)

    offsets
    |> parse_offsets()
    |> Enum.any?(fn offset -> days <= offset end)
  end

  # Defensive even though Type validates at write time (fix 4): skip non-integer/blank tokens
  # rather than raising on the render path. Empty/nil → a sane default offset.
  def parse_offsets(nil), do: [7]
  def parse_offsets(str) do
    parsed =
      str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(fn tok ->
        case Integer.parse(tok) do
          {n, ""} when n >= 0 -> [n]
          _ -> []
        end
      end)

    if parsed == [], do: [7], else: parsed
  end
end
```

- [ ] **Step 3: UrgencyBadge component** — red for `:overdue`, amber for `:due_soon`, hidden for `:ok`

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

---

## Task 15: Dashboard LiveView (split view)

**Files:**
- Create: `lib/argus_web/live/dashboard_live/index.ex`
- Create: `test/argus_web/live/dashboard_live_test.exs`

- [ ] **Step 1: Test renders My work and Team overview tabs**

Member default tab: `my_work`. Manager default: `team`.

- [ ] **Step 2: Queries**

Filter is **live cycles only**, composed via `Obligations.live/1` (the single definition of
`status == "active" AND is_nil(completed_at)` from Task 8) — never hand-write the predicate, or a
`status`-only query will leak completed obligations onto the dashboard forever. Both queries take
the scope and filter by `scope.entity`/`scope.user`:

```elixir
def list_my_work(%Scope{entity: entity, user: user}) do
  Obligation
  |> live()
  |> where([o], o.entity_id == ^entity.id)
  |> where([o], o.primary_assignee_id == ^user.id or o.id in subquery(collaborator_ids(user)))
  |> order_by([o], asc: o.due_by)
end

def list_team_overview(%Scope{entity: entity}) do
  Obligation
  |> live()
  |> where([o], o.entity_id == ^entity.id)
  |> order_by([o], asc: o.due_by)
end
```

- [ ] **Step 3: UI** — table with title, type, assignee, due_by, `<.urgency_badge>`. Compute
  `today = Urgency.today_for(entity.timezone)` **once** in `mount` and pass it to every
  `classify/3` call (fix 3). **Sort in Elixir, not SQL:** the query's `order_by: due_by` is only a
  pre-sort — urgency is not a column, so after `classify/3` re-sort overdue → due_soon → `due_by`
  asc in the LiveView. Don't rely on the SQL `order_by` alone for the urgency tiers.

- [ ] **Step 4: Commit**

---

## Task 16: Obligation LiveViews (form, show, workflow)

**Files:**
- Create: `lib/argus_web/live/obligation_live/form.ex`
- Create: `lib/argus_web/live/obligation_live/show.ex`
- Create: `lib/argus_web/live/obligation_live/index.ex`
- Create: `test/argus_web/live/obligation_live_test.exs`

- [ ] **Step 1: Form** — manager-only; fields: title, type, primary assignee, collaborators (multi-select), due_by, open_note.

- [ ] **Step 2: Show page sections**

1. Header — title, type, due_by, assignees
2. Event timeline — open → in_progress → done/cancelled
3. Documents per event
4. Actions (role-gated): Start progress, Add note/doc, Done (modal with next due date picker), Cancel, End series

- [ ] **Step 3: Done modal**

- "Recurring?" is read from the **live `recurring_interval` on the type** (`Recurrence.recurring?/1`),
  **not** the obligation snapshot — this must match `complete/3`'s guard exactly, or after a
  mid-cycle type edit the modal and backend disagree (modal asks for a date the backend won't
  require, or vice-versa). Completion *rules* use the snapshot; the recurrence *decision* uses the
  live type (see the snapshot-vs-live note in Task 8 / spec).
- If recurring **and series not ended**: show a date input that is **required** — the modal
  cannot be submitted without a next due date (mirrors the `{:error, :next_due_required}` guard
  in `complete/3`, fix 5). To finish a recurring obligation *without* a successor, the user picks
  **End series** instead, not blank-submit.
- Pre-fill via `Recurrence.next_due_suggestion/2` for fixed intervals; blank for `custom` (user must pick)
- Enforce note/doc fields against the **obligation's snapshot** on submit (not the live type —
  matches `Completion` in Task 9). When the snapshot lists `complete_documents` slots, the upload
  UI must **require a slot selection** so a slotless early upload can't cause a mystifying Done
  failure (see #10); the Done error names any still-missing slots.

- [ ] **Step 4: LiveView tests** for create, start_progress, complete with spawn, and that the
  Done modal blocks submit when a recurring obligation has no next due date

- [ ] **Step 5: Commit**

---

## Task 17: Obligation types management UI

**Files:**
- Create: `lib/argus_web/live/obligation_type_live/index.ex`
- Create: `lib/argus_web/live/obligation_type_live/form.ex`

- [ ] **Step 1: Index** — list system presets (read-only) + entity custom types

- [ ] **Step 2: Form** — manager/admin clone or create; fields per Type schema including interval
  select with all 8 values. Because `recurring_interval` is read **live**, switching a type to
  **One-off (`none`)** stops the chain for **every** live obligation of that type after its next
  Done (no successor spawns) — without setting `series_ended_at`. Surface a one-line hint on the
  interval field (e.g. "Switching to one-off stops recurrence for all open obligations of this
  type after their next Done") so this isn't surprising; it differs from **End series**, which
  cancels a single in-flight cycle.

- [ ] **Step 3: Commit**

---

## Task 18: Membership management UI

**Files:**
- Create: `lib/argus_web/live/membership_live/index.ex`

- [ ] **Step 1: List members, invite form (email + role), pending invitations**

- [ ] **Step 2: Admin can change roles. `seat_limit` is enforced through the single
  `Entities.seats_available?/1` gate on every path that adds an active member — invite **and**
  invitation acceptance (re-checked at accept time) **and** any direct membership creation — not
  just the invite form (fix #15). Role changes don't add a seat, so they're exempt.

- [ ] **Step 3: Commit**

---

## Task 19: Series history on obligation show

**Files:**
- Modify: `lib/argus_web/live/obligation_live/show.ex`

- [ ] **Step 1: Sidebar or tab "Series history"** — `Obligations.list_series(series_id)` ordered by `due_by`

- [ ] **Step 2: Link to completed obligations (read-only view)**

- [ ] **Step 3: Commit**

---

## Task 20: Desktop & Mobile layouts (daisyUI, peggy)

> All Desktop LiveViews (Tasks 15–19) wrap content in
> `<Layouts.app flash={@flash} current_scope={@current_scope}>`; the generated shell works from
> Task 1, so those tasks need no layout of their own — this task **refines** the shells. Build with
> daisyUI classes; never `@apply`. Mirror `peggy/lib/peggy_web/components/layouts.ex`.

**Files:**
- Modify: `lib/argus_web/components/layouts.ex`
- Modify: `lib/argus_web/components/core_components.ex` (daisyUI inputs/buttons/modal/icon — generated)

- [ ] **Step 1: `Layouts.app/1`** — top `navbar`: app logo, active entity name + slug, entity
  switcher, locale switcher, **Mobile** toggle link (sets `argus_view=mobile`), settings, log out.
  `<.flash_group>` lives only here. Content wrapper `mx-auto max-w-5xl space-y-4`, responsive
  padding `px-4 sm:px-6 lg:px-8`.
- [ ] **Step 2: `Layouts.mobile_app/1`** — `min-h-screen bg-base-100 pb-20`, fixed
  `mobile_bottom_nav` (grid of tabs: Dashboard / Obligations / More, `hero-*` icons,
  `pb-[env(safe-area-inset-bottom)]`), and a "More" sheet (theme, switch entity, **Desktop**
  toggle, log out). Large touch targets.
- [ ] **Step 3: Commit**

---

## Task 21: Mobile UI LiveViews (/m/:entity_slug)

**Files:**
- Create: `lib/argus_web/live/mobile_live/{dashboard,obligations,obligation_show}.ex`
- Create: `test/argus_web/live/mobile_live_test.exs`

- [ ] **Step 1: `MobileLive.Dashboard`** — same `Obligations.list_my_work/list_team_overview`
  queries and `today_for(entity.timezone)` urgency as the desktop dashboard, rendered in
  `Layouts.mobile_app` with `active={:home}`: a single scrollable list of live cycles, big
  urgency badges, sticky search header. Reuse the context — no new queries.
- [ ] **Step 2: `MobileLive.Obligations` / `ObligationShow`** — touch-friendly list + the same
  open → in_progress → done workflow actions (role-gated via `@current_scope.role`); Done modal
  requires next_due_by for recurring (same rule as Task 16).
- [ ] **Step 3: LiveView tests** — mobile dashboard renders; device auto-route redirect
  (`AutoRouteByDevice`) sends a mobile UA from `/entities/:slug` to `/m/:slug`.
- [ ] **Step 4: Commit**

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Users without timezone | Task 3 |
| Entities, memberships, invitations | Task 4 |
| Roles admin/manager/member | Task 6 |
| Primary + collaborators | Task 8 |
| Done: primary or manager | Task 6, 9 |
| Obligation types + intervals | Task 7, 13, 17 |
| custom interval manual date | Task 7, 16 |
| Event workflow open/in_progress/done | Task 8, 9, 16 |
| Recurrence spawns new obligation | Task 9 |
| series_id linking | Task 8, 9, 19 |
| Cancel + end series | Task 10 |
| Completion rules on Done | Task 9 |
| Completion rules snapshotted at creation (type edits don't move the bar) | Task 8, 9 |
| Done docs counted across all cycle events (incremental uploads) | Task 9, 11 |
| start_progress idempotent (one-step-forward) | Task 9 |
| Spawn race → clean `:not_live` (no raw Ecto error) | Task 9 |
| Entity soft-delete filtered from lookups/resolver | Task 4, 5 |
| seat_limit enforced on invite + accept + direct add | Task 4, 18 |
| Mobile = field-work only; management Desktop-only (whitelist) | Task 5, 21 |
| Live-cycle predicate defined once (`Obligations.live/1`) | Task 8, 15 |
| Terminal `completed_at` (dashboards exclude done cycles) | Task 8, 9, 15 |
| One live cycle per series (partial unique index) | Task 8, 9 |
| Idempotent / concurrency-safe Done | Task 9 |
| Recurring Done requires next_due_by (no series limbo) | Task 9, 16 |
| Urgency uses entity timezone | Task 14, 15 |
| CSV type fields validated at write time | Task 7 |
| Incremental documents + void | Task 11 |
| Audit log corrections | Task 12 |
| Dashboard urgency badges | Task 14, 15 |
| Dashboard split view | Task 15 |
| Lock after Done | Task 12 |
| Magic-link-first onboarding, password fallback (peggy) | Task 3 |
| Scope struct (`@current_scope`) | Task 3, 5 |
| Dual Desktop/Mobile UI + device auto-route | Task 5, 20, 21 |
| daisyUI 5 layouts (app + mobile_app) | Task 20 |

## Deferred (spec open items)

- In-app notifications / Oban reminder jobs → out of scope v1
- Email/SMS notifications → out of scope
- Subjects → out of scope

---

## Final verification

- [ ] `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test) — peggy convention
- [ ] Run credo: `mix credo` (add if desired)
- [ ] Manual smoke (Desktop): register (email) → click magic link in mailbox → create entity →
  create type → create obligation → progress → done → verify spawn → verify dashboard urgency badges
- [ ] Manual smoke (Mobile): visit `/m/:entity_slug` (or load on a phone UA) → bottom-nav dashboard,
  obligation workflow, Desktop toggle round-trips via `argus_view` cookie

```bash
mix phx.server
```