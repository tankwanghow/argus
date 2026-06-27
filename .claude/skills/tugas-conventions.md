---
name: tugas-conventions
description: House conventions for building Tugas — use whenever implementing or reviewing Tugas code (contexts, schemas, auth/onboarding, LiveViews, Desktop/Mobile UI, CSS). Mirrors the sibling Phoenix projects in ~/Projects/elixir, primarily peggy (UI, onboarding, scope) and full_circle (contexts, authorization).
---

# Tugas House Conventions

Tugas follows the conventions of the user's other Phoenix 1.8 / LiveView 1.2 apps in
`~/Projects/elixir`. **peggy** is the primary reference for UI, onboarding, and request scope;
**full_circle** for context/authorization shape. When in doubt, open the corresponding peggy file
and match it. Peggy's full Phoenix 1.8 ruleset lives in `~/Projects/elixir/peggy/AGENTS.md` — its
rules apply to Tugas too.

## Stack

- Elixir 1.19 / OTP 28, Phoenix 1.8.5, LiveView 1.2.1, Ecto 3.13, PostgreSQL (citext).
- **Tailwind v4 + daisyUI 5.** No `tailwind.config.js`; use `@import "tailwindcss"` + `@source`
  directives in `app.css`. Never `@apply`. Build UI from daisyUI classes (`btn`, `card`, `badge`,
  `modal`, `navbar`, `alert`, `input`, `fieldset`, …) and the shared `core_components.ex` /
  `layouts.ex` — don't hand-roll equivalents. This means the app is generated **with assets**
  (do NOT pass `--no-assets` to `mix phx.new`).
- Only `app.js` / `app.css` bundles. Vendor deps import into those. Never reference external
  `src`/`href` in layouts; never inline `<script>` — use colocated hooks
  (`:type={Phoenix.LiveView.ColocatedHook}`).
- **daisyUI 5 renamed/removed several v4 class names — they fail silently (no compile error,
  just unstyled output).** Don't carry v4 names over from older snippets. Known traps:
  `tabs-boxed` → **`tabs-box`**; the `*-bordered` modifiers are **gone** (border is the default —
  use plain `select` / `input` / `textarea` / `file-input`, never `select-bordered` etc.);
  `card-bordered` → `card-border`; `form-control` is dropped (use `fieldset`). `core_components.ex`
  already uses the correct v5 names — match it rather than inventing classes.
- HTTP: `Req` only.

## Shared workspace toolchain (`~/Projects/elixir`)

All sibling projects share **one pinned set of asset binaries** instead of each installing its own.
Tugas must wire into it the same way (mirror peggy's `mix.exs` + `config/config.exs`).

- **`~/Projects/elixir/.global_assets/`** — pinned binaries populated by `.global_assets/setup.sh`:
  esbuild **0.28.1**, tailwindcss **4.3.1** (linux x64 + arm64), heroicons **v2.2.0** (`optimized`).
  Run `~/Projects/elixir/.global_assets/setup.sh` once after cloning (idempotent; binaries are
  git-ignored). **Add `tugas` to that script's `link_heroicons` project list.** (The mix.exs path
  below also self-heals the `deps/heroicons` symlink on `deps.get`, so it works even before the
  script edit.)
- **`~/Projects/elixir/shared_config/`** — `workspace_assets.ex` (the `WorkspaceAssets` module),
  `assets.exs` (sets `:esbuild`/`:tailwind` `path:` to the global binaries), `prod_arm64.exs`
  (pou_con only). Do not duplicate this in Tugas — reference it.
- **`~/Projects/elixir/mise.toml`** pins elixir 1.19.5-otp-28 / erlang 28.3.1 — Tugas inherits it.
- **`config/config.exs`** — top of file, before the esbuild/tailwind profiles:

  ```elixir
  workspace_assets_config = Path.expand("../../shared_config/assets.exs", __DIR__)
  if File.exists?(workspace_assets_config) do
    import_config workspace_assets_config           # use shared global binaries
  else
    config :esbuild, version: "0.28.1"              # standalone fallback
    config :tailwind, version: "4.3.1"
  end
  ```
  Profiles are named `tugas` (`config :esbuild, tugas: [...]`, `config :tailwind, tugas: [...]`).
  Also set `config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase` (urgency needs real
  zones via `DateTime.now/1`).
- **`mix.exs`** — replace the generated heroicons dep with `heroicons_dep()` and add the helpers
  `workspace_assets?/0`, `load_workspace_assets!/0`, `heroicons_dep/0`, `assets_setup_tasks/0`
  (each falls back to the stock github/hex install when `shared_config` is absent — copy peggy's
  verbatim). Aliases: `"assets.setup": assets_setup_tasks()`, `"assets.build": ["compile",
  "tailwind tugas", "esbuild tugas"]`, matching `assets.deploy`, and `precommit`.
- daisyUI 5 + daisyUI-theme + the heroicons plugin are vendored under `assets/vendor/` and loaded
  via `@plugin` in `app.css` (stock Phoenix 1.8 output) — keep that, just match peggy's themes.

## Schema & contexts

- `use Tugas.Schema` (binary_id PK, `@foreign_key_type :binary_id`). Mirrors `FullCircle.Schema`.
  Tugas additionally sets `@timestamps_opts [type: :utc_datetime]` (the spec uses utc_datetime
  throughout) — this is the one intentional divergence from full_circle's naive default.
- Domain logic lives in context modules (`Tugas.Accounts`, `Tugas.Entities`, `Tugas.Duties`).
  LiveViews call contexts, never `Repo` directly.
- **Bespoke context functions** (decided), all **scope-first**: `create_duty/2`,
  `complete/3`, `skip/3`, `end_series/3`, `start_progress/2`, etc. (scope replaces the old
  entity+actor args) — Tugas does NOT adopt full_circle's generic `StdInterface`.
- Multi-step writes use `Ecto.Multi`/transactions.
- **Return conventions (house style):**
  - success → `{:ok, struct}`
  - validation → `{:error, %Ecto.Changeset{}}`
  - failed Multi → `{:error, failed_op, failed_value, changes_so_far}`
  - **unauthorized → `:not_authorise`** (full_circle's spelling — use this exact atom, not
    `{:error, :unauthorized}`)
- Programmatic fields (`entity_id`, `user_id`, `series_id`) are **set explicitly when building the
  struct, never in `cast`** (security; peggy/Ecto rule).
- Generate migrations with `mix ecto.gen.migration <name_underscored>`.

## Authentication, scope & onboarding (peggy model)

Tugas uses Phoenix 1.8 `phx.gen.auth` **magic-link-first** onboarding, exactly like peggy, **with
password as a fallback** login method. Registration is email-only (no password) and the emailed
login link is the primary path; a user may *optionally* set a password later (settings) and then
log in with it as an alternative. This is the stock `phx.gen.auth` 1.8 behavior — keep both, do
not remove the password path.

- **Onboarding flow:**
  1. Register with **email only** (`UserLive.Registration` collects just email; `<.input
     type="email">`). No password at registration.
  2. `Accounts.register_user/1` then `Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))`
     emails a login link.
  3. `UserLive.Confirmation` (the `/users/log-in/:token` view) confirms the account and logs in
     ("Confirm and stay logged in" vs "only this time" → remember-me).
  4. After sign-in, user lands on entity selection / creation; first entity they create becomes
     their default membership (admin).
- **Login (`UserLive.Login`)** offers **both**: request a magic link by email (primary), and — for
  users who have set one — an email + password form (fallback). `hashed_password` stays nullable.
  `UserLive.Settings` is where a password is added/changed (sudo-mode reauth).
- **Scope struct** — `Tugas.Accounts.Scope` (mirror `Peggy.Accounts.Scope`):
  `defstruct user: nil, entity: nil, membership: nil, role: nil`, with `for_user/1`,
  `put_entity/3` (sets `role` from membership), `member?/1`. Contexts take `scope` (or
  `current_scope`) as the **first argument** and filter queries by `scope.user` / `scope.entity`.
- **`@current_scope` everywhere** — never `@current_user`/`@current_company`/`@current_role` in
  templates. Access the user as `@current_scope.user`, entity as `@current_scope.entity`, role as
  `@current_scope.role`.
- **Router** uses `phx.gen.auth` plugs + `live_session` blocks: `:fetch_current_scope_for_user`
  in `:browser`; a `live_session :current_user` (on_mount `mount_current_scope`) for
  with-or-without-auth pages; a `live_session :require_authenticated_user` (on_mount
  `require_authenticated`) for authed pages; and an entity-scoped `live_session` whose on_mount
  resolves the `:entity_slug` to `scope.entity` + membership (replacing the old standalone
  `SetActiveEntity` plug). State which `live_session`/pipeline a route goes in and why.
- Authorization is **scope-first**: `Tugas.Authorization.can?(%Scope{}, :action)` (entity-level)
  and `can?(%Scope{}, :action, %Duty{})` (duty-scoped). Pattern-matched clauses
  (mirroring `FullCircle.Authorization`'s shape) keyed off the **pre-resolved `scope.role`**, with
  an `allow_roles(scope, ~w(admin manager)a)` helper — Tugas does **not** re-query the role from
  the DB on every call the way full_circle does, because the `on_mount` already put it on the
  scope. Roles: `admin | manager | member`. Contexts return `:not_authorise` on denial.

## Dual interface — Desktop + Mobile (peggy model)

Two UIs share the same contexts/schemas, each with its own LiveViews and layout:

- **Desktop** under `/entities/:entity_slug/...` — `TugasWeb.EntityLive.*` / `DutyLive.*` /
  `DashboardLive.*`. Top `navbar` via `Layouts.app/1`. Wider layouts (`mx-auto max-w-5xl`),
  responsive padding (`px-4 sm:px-6 lg:px-8`).
- **Mobile** under `/m/:entity_slug/...` — `TugasWeb.MobileLive.*`. `Layouts.mobile_app/1` shell:
  `min-h-screen bg-base-100 pb-20`, a fixed bottom tab nav (`mobile_bottom_nav`, a `grid-cols-5`
  of five primary tabs — Todo · Todos · Duty · Duties · More — with emoji glyphs and
  `pb-[env(safe-area-inset-bottom)]`), and a "More" sheet for theme/switch-entity/log-out plus
  secondary links (members, types, team logs). Large touch targets, sticky page header with search.
- **Shared non-render logic across the two UIs lives in a `*.IndexHelpers` module** that both the
  desktop and mobile LiveView delegate to, so the only per-UI code is `render/1` + thin
  `handle_event` wiring. Duties use `DutyLive.{IndexHelpers,CreateForm}`; todos use
  `TodoLive.IndexHelpers` (+ `ActivityFormat`). When adding a feature with both UIs, follow this
  split rather than duplicating mount/load/handler logic.
- **`AutoRouteByDevice` plug** (mirror peggy's) in the authed pipeline: redirects `/entities/<slug>`
  → `/m/<slug>` for mobile UAs and vice-versa, honoring a `tugas_view=mobile|desktop` cookie set by
  explicit Mobile/Desktop toggle links. Only redirect when the counterpart route exists (whitelist
  of mobile-capable tails) so single-UI pages never 404.
- Every template begins with `<Layouts.app flash={@flash} current_scope={@current_scope}>` (desktop)
  or `<Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>` (mobile).
  `<.flash_group>` is only ever called inside `layouts.ex`.

## LiveView idioms

- `use TugasWeb, :live_view`; the `:app` layout is set in the `use` macro (web.ex), as in
  full_circle.
- **Forms:** always `to_form/2` in the LiveView + `<.form for={@form}>` + `<.input>` in the
  template. Never pass a changeset to `<.form>`. Override input classes fully if you override at all.
- **Icons:** always `<.icon name="hero-..." />`; never the `Heroicons` module.
- **Collections:** Phoenix **streams** (`stream/3` + `phx-update="stream"`); never
  `phx-update="append"`. The dashboard is the reference pattern (`DashboardLive.Index` /
  `MobileLive.Dashboard`): the context exposes a **keyset-paginated** loader
  (`Duties.list_duties_page/2` returning `%{rows, cursor, end?}`, opaque cursor via
  `Duties.Pagination`); the LiveView holds `@cursor`/`@end?`/`@empty?`, streams the first page
  on mount/filter-change (`stream(:rows, page, dom_id: &dom_id/1, reset: true)`) and appends on a
  `phx-viewport-bottom={!@end? && "load_more"}` sentinel (`stream(:rows, page, dom_id: &dom_id/1,
  at: -1)` — pass the same `dom_id:` on both so ids stay stable; page size 25). The empty state is a
  **sibling** `<div :if={@empty?}>` of the stream `<ul>` (never inside it). Pass an explicit `id` to
  any per-row component so the stream dom_id lands on its root element. SQL-side filtering/sorting is
  the default; in-memory sorting is the exception (urgency over a bounded window — see CLAUDE.md's
  dashboard section).
- **Someday / dateless duties (gotchas).** `Duty.due_by` is **nullable**; a duty is "Someday"
  when `due_by IS NULL` (created via the virtual `:someday` checkbox, which force-nils `due_by` and
  drops the requirement in `Duty.changeset/2`). Two traps that crash/corrupt if forgotten:
  - **Anything reading `due_by` for a live cycle must nil-guard it.** `Urgency.classify/3` & `tier/3`
    return `:none` for nil; `Recurrence.next_due_suggestion(_type, nil)` returns nil (the done/skip
    show-form pre-fill calls it at mount, so a missing nil clause crashes the show page for a
    *recurring* Someday duty). Render guards: `:if={@live? and @duty.due_by}` on urgency
    badges, `:if={@duty.due_by}` on "due …" text. `format_date(nil)` is already safe ("—").
  - **The virtual `:someday` field leaks into `changeset.changes`.** `update_duty/3`'s
    audit-log loop must `Map.drop(changeset.changes, [:someday])` so edits don't write a bogus
    `"someday"` AuditLog row. Apply the same care to any new loop over `changeset.changes` that
    touches a changeset carrying virtual fields.
  - **Someday is a sort, not a filter.** There is no date filtering — every lifecycle list
    (Live/Completed/Skipped/All) includes dateless duties. The `Someday` sort
    (`apply_page_order(:someday)` → `asc_nulls_first: due_by`) floats them to the **top**; `due_asc`/
    `due_desc` keep `NULLS LAST` (dateless at the bottom). When the list can contain dateless rows,
    any in-memory sort that loads only dated rows (e.g. the urgency window) must surface them somewhere
    or they silently vanish — the urgency tail does this with `due_after_or_null` (dateless last).
    See CLAUDE.md's dashboard section.
- **Datetimes render in the entity timezone.** Stored `DateTime`s are UTC. In views, format them
  with `TugasWeb.CoreComponents.format_datetime(dt, @current_scope.entity.timezone, format)`
  (`format` = `:default`/`:short`) — it shifts via `in_zone/2` (UTC fallback for a blank/invalid
  zone). A stored datetime shown as a *day* (invite expiry, completion date) uses
  `format_zoned_date/3` (shift **then** `to_date`). **Never `Calendar.strftime` a raw UTC
  datetime.** `format_date/2` is for bare `Date`s only (`due_by`) — no shift. Shared components that
  print datetimes (`cycle_badge`, `todo_team_activity`, `duty_document_row` voided rows,
  mobile `duty_card`, dashboard `duty_row_link`) take a `timezone` attr threaded from
  the caller's `@current_scope`; don't reach for `@current_scope` inside a function component that
  wasn't given it. Pairs with the render-time `Urgency.today_for(entity.timezone)` rule.
- Gettext on **all** user-facing text — `gettext("...")` / `{gettext(...)}`. Locale in session
  (`set_locale`); English default, structured for more locales.
- Rebind block results (`socket = if connected?(...) do ... end`); no `String.to_atom/1` on user
  input; predicates end in `?`; `Enum.at` not `list[i]`; direct field access on structs (no
  `struct[:field]`).

## Documents (uploads UI)

Duty documents live in **two surfaces**, split by purpose; each file appears in
exactly one place (no duplicated rows/checklists):

- **Completion Documents** — `TugasWeb.DutyCompletionDocuments`, cycle-level
  (one modal per duty). A row per **required** slot: the live file inline
  (download + Delete/Void) or an inline uploader if the slot is unsatisfied, plus a
  voided-required section. Slot uploads attach to the cycle's current workable event
  (`DocumentHelpers.upload_event/1` → `in_progress` else `open`).
- **Step Files** — `TugasWeb.DutyStepFiles`, per-step (a modal per timeline
  event). That event's **supporting** files (no-slot or stale-slot) + a voided-other
  section + an additional-file uploader.

Rules:
- Classification/partitioning is pure and lives in
  `TugasWeb.DutyLive.DocumentHelpers` (`completion_view/2`, `step_files/2`,
  `parse_slots/1`). A doc is **required** iff its `document_slot` is in the
  duty's **current snapshot** `complete_documents`, else **supporting**.
- **Slots are immutable after upload; there is no Replace and no slot editing.** To
  change a slot's file, delete (within 48h) or void it, then re-upload — uploading is
  only offered for an unsatisfied slot.
- **Voided files are kept and remain downloadable** (`DocumentController` serves them;
  do not reintroduce a voided→404 guard).
- Admin type edits: `Duties.propagate_complete_documents_to_live/3` updates the
  snapshot of **live** duties only (completed/closed frozen); a removed/renamed
  slot reclassifies its file required → supporting **without mutating the row** (re-adding
  the slot re-links it).
- Create-form attachments are LiveView upload entries **consumed on save** (no disk
  staging). One `:document` `allow_upload` config per LiveView; only one Documents
  modal is open at a time.

## Before finishing

- Run `mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, `format`, `test`)
  before declaring changes done — peggy convention.
- TDD per the implementation plan: failing test → implement → pass → one commit per task.

## Reference files (read these when matching a pattern)

- Onboarding/auth: `peggy/lib/peggy_web/live/user_live/{registration,confirmation,login}.ex`,
  `peggy/lib/peggy/accounts/scope.ex`, `peggy/lib/peggy_web/router.ex`
- Dual UI / layouts: `peggy/lib/peggy_web/components/layouts.ex` (`app/1`, `mobile_app/1`,
  `mobile_bottom_nav`), `peggy/lib/peggy_web/plugs/auto_route_by_device.ex`
- Contexts/auth shape: `full_circle/lib/full_circle/authorization.ex`,
  `full_circle/lib/schema.ex`
- Phoenix 1.8 ruleset: `peggy/AGENTS.md`
