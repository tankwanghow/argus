# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Argus is **built**: the Phoenix app is generated and the full 21-task implementation plan has
been executed (contexts, schemas, auth/scope, dual Desktop+Mobile LiveViews, dashboard urgency,
obligation workflow/recurrence, types & membership management, audit, uploads). `mix precommit`
passes. What remains is the plan's two **manual smoke tests** (Desktop and Mobile happy-paths via
`mix phx.server`) and any future enhancements beyond v1 scope.

- **Spec:** `docs/superpowers/specs/2026-06-13-argus-design.md` — authoritative for data model, roles, and workflows.
- **Plan:** `docs/superpowers/plans/2026-06-13-argus-implementation.md` — 21 phased, TDD, commit-per-task steps (all complete).

When extending the app, follow the `argus-conventions` skill and keep the TDD/commit-per-change
rhythm; run `mix precommit` before declaring work done.

## House conventions (read first)

Argus follows the conventions of the sibling Phoenix apps in `~/Projects/elixir` — primarily
**peggy** (UI, magic-link onboarding, request scope, Desktop/Mobile dual interface) and
**full_circle** (context & authorization shape). The authoritative, detailed convention guide is
the **`argus-conventions` skill** (`.claude/skills/argus-conventions.md`) — consult it before
writing non-trivial code. Peggy's full Phoenix 1.8 ruleset (`~/Projects/elixir/peggy/AGENTS.md`)
applies here too. Headlines:

- **Tailwind v4 + daisyUI 5** (no `tailwind.config.js`; daisyUI component classes). App is
  generated **with assets and mailer** — not `--no-assets`/`--no-mailer`.
- **Magic-link-first onboarding, password fallback** (peggy / `phx.gen.auth` 1.8): register with
  email → emailed login link → confirm → land on entity create/select. Login also accepts an
  email+password (fallback) once a user sets a password in settings; `hashed_password` stays
  nullable. A `%Argus.Accounts.Scope{user, entity, membership, role}` struct flows as
  `@current_scope`; never `@current_user`/`@current_role` in templates.
- **Dual UI:** Desktop `/entities/:entity_slug/...`, Mobile `/m/:entity_slug/...`, with an
  `AutoRouteByDevice` plug + a `argus_view` cookie override. Separate LiveViews + layouts
  (`Layouts.app/1` navbar, `Layouts.mobile_app/1` bottom-nav shell).
- LiveView: `to_form` + `<.form>`/`<.input>`, `<.icon name="hero-...">`, streams (never append),
  colocated hooks. Unauthorized context calls return **`:not_authorise`**.
- Run `mix precommit` before declaring work done.

## Commands (post-bootstrap)

```bash
~/Projects/elixir/.global_assets/setup.sh   # once: fetch shared esbuild/tailwind/heroicons binaries
mix setup                             # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server                        # run app (localhost:4000)
mix test                              # full suite (auto creates/migrates test DB)
mix test test/argus/obligations_test.exs            # single file
mix test test/argus/obligations_test.exs:42         # single test by line
mix precommit                         # compile --warnings-as-errors, deps.unlock --unused, format, test
```

**Shared toolchain:** assets (esbuild 0.28.1, tailwindcss 4.3.1, heroicons v2.2.0) are pinned once
under `~/Projects/elixir/.global_assets` and wired in via `~/Projects/elixir/shared_config` — the
same setup every sibling project uses. `config/config.exs` imports `shared_config/assets.exs` and
`mix.exs` resolves heroicons through `WorkspaceAssets`; both fall back to standalone installs if
the workspace dirs are absent. Toolchain versions come from `~/Projects/elixir/mise.toml`.

Tech stack: Elixir 1.19 / OTP 28, Phoenix 1.8.5, LiveView 1.2.1, Ecto 3.13, PostgreSQL (citext), Tailwind v4 + daisyUI 5, Swoosh mailer (magic-link login), Req.

## Architecture

Phoenix LiveView monolith, PostgreSQL, **binary_id (UUID) primary keys everywhere** via the
`Argus.Schema` macro (`use Argus.Schema`). No background jobs, no REST API, no notification
system in v1.

### Multi-tenancy & scope

Tenants are **entities**. Desktop routes are scoped `/entities/:entity_slug/...`, mobile
`/m/:entity_slug/...`. An entity-scoped `live_session` `on_mount` resolves the slug, verifies the
user's membership, and builds a `%Argus.Accounts.Scope{user, entity, membership, role}` exposed as
`@current_scope` (peggy pattern — replaces a standalone plug + ad-hoc `active_entity`/`membership`
assigns). Contexts take `scope`/`current_scope` as their first argument; authorization keys off
`scope.role`, never a global user attribute.

- `Argus.Accounts` — users (email + **magic-link login tokens**; optional password; locale;
  **no timezone on users**), `Scope` struct, `register_user/1`, `deliver_login_instructions/2`.
- `Argus.Entities` — entities (soft-deleted via `deleted_at`; all lookups filter `deleted_at IS NULL`), memberships `(user_id, entity_id, role)`, invitations. One default entity per user (partial unique index). `create_entity/2` also inserts the creator's `admin` membership. `seat_limit` is enforced via a single `seats_available?/1` gate on invite **and** accept **and** direct add.
- `Argus.Authorization` — **scope-first**: `can?(scope, action)` / `can?(scope, action, obligation)`. Keys off the pre-resolved `scope.role` (no per-call DB lookup). Single source of truth for role rules; see the role table below. Unauthorized mutations return `:not_authorise`.

### Roles

| Role | Can |
|------|-----|
| admin | everything |
| manager | create/edit obligations, manage types, mark Done on **any** obligation, cancel, **skip cycle**, end series |
| member | view assigned work, add notes/docs while in progress, mark Done **only if primary assignee** |

Collaborators (join table) can move an obligation to `in_progress` and add notes/docs, but
**cannot** mark Done. Only the **primary assignee** or a manager/admin marks Done.

**Obligations may be unassigned.** `primary_assignee_id` is **nullable** — an obligation can be
created without a primary assignee and assigned later (`Obligations.list_unassigned/1` surfaces
these; the title search matches the literal `"unassigned"`). An unassigned cycle has **no member
who can mark it Done** — only a manager/admin can (or after a primary assignee is set). The
`mark_done` / `start_progress` authorization checks guard `nil` before comparing
`primary_assignee_id` to the user.

**Every state transition requires a note.** Creating an obligation (the `open_note`),
`start_progress`, cancel, **skip**, and end-series all reject a blank note via
`validate_action_note`. The Done note is likewise **always required** (see rule 1). Notes are no
longer optional context — treat them as mandatory on every write that produces an `Event`.

**Skip cycle** (`Obligations.skip_cycle/3`, manager/admin) cancels the current live cycle (with a
note) **and** spawns the next cycle in the series in one transaction — the recurrence equivalent of
"close this cycle without doing the work." It requires a recurring, not-ended series and a
`next_due_by`, mirroring the Done→spawn path.

### Obligations domain — the core model (read the spec before editing)

The single most important design decision: **one `Obligation` row per cycle**, not a standing
series with a rolling `due_by`. A recurrence chain is linked by a shared `series_id` (UUID).

- `Argus.Obligations.Obligation` — one cycle. `status` is `active | cancelled`; **done-ness is a separate `completed_at` timestamp**, not a status value (a completed cycle keeps `status = active`). A cycle is **live** while `status = active AND completed_at IS NULL` — that's the set dashboards show and that can be worked/completed/cancelled. This predicate is defined **once** as `Obligations.live/1` (a composable query builder) and every list/dashboard/report composes it — never hand-write it. A partial unique index on `series_id` (where live) enforces **one live cycle per series**. `series_ended_at` (when set) blocks future spawning. The row also **snapshots** `complete_documents` from the type at creation (see rule 1). `primary_assignee_id` is **nullable** (unassigned obligations).
- `Argus.Obligations.Event` (`obligation_events`) — **append-only forward-only** status steps: `open → in_progress → done | cancelled`. New status = new row; rows are never deleted and status is never rewritten. The step `note` lives here (open context, done comment, cancel reason). `start_progress` is guarded — it only steps an `open` cycle forward, so double-clicks can't create duplicate `in_progress` rows.
- `Argus.Obligations.EventDocument` — file uploads attached to an event; the per-file column is **`file`** (a `%{filename, original, path}` map), not `documents`. Wrong files are **voided** (`voided_at`/`voided_by_id`/`void_reason`), never deleted. `document_slot` matches a name in the obligation's snapshotted `complete_documents` for Done validation.
- `Argus.Obligations.AuditLog` — field-level before/after for **corrections** (title, due_by, assignee, note edits).
- `Argus.Obligations.Type` — **per-entity only** (`entity_id` is **NOT NULL**). There are no
  global system presets; instead, when an entity is created, `Argus.Obligations.SampleTypes`
  seeds a private copy of the sample types into that entity (`seed_for_entity/1`, run inside the
  `create_entity` `Ecto.Multi`). Every entity therefore owns and can edit its full type set —
  `list_types`/`get_type!` filter strictly by `entity_id`, and there is no "immutable preset"
  case any more.

### Three rules that are easy to get wrong

1. **Done validation is enforced only on Done**, never earlier. A Done **note is always
   required** (blank ⇒ `{:error, :note_required}`) — this is unconditional and no longer
   type-configurable (`complete_note_required` has been removed from both the type and the
   obligation snapshot). The only **snapshotted** completion rule is `complete_documents` (copied
   from the type at creation), validated against the obligation's snapshot, **not the live type**
   — editing a type must not retroactively move the bar for a live cycle (type-definition audit is
   out of scope). `complete_documents` (comma-delimited slot names) → one **non-voided** document
   per named slot, counted across **all events in the cycle** (open/in_progress/done), so
   incremental uploads count. Each spawned cycle re-snapshots from the type. See
   `Obligations.Completion`. **Only the completion contract is frozen** — `reminder_offsets`
   (display) and `recurring_interval` (shape of the next cycle) are read **live** from the type by
   design; see the snapshot-vs-live note in the spec.

2. **Recurrence on Done.** Done is a **guarded close**: a conditional `update_all` stamps
   `completed_at` only `WHERE completed_at IS NULL` — 0 rows updated ⇒ `{:error, :not_live}`,
   making Done idempotent and concurrency-safe. If `Recurrence.recurring?(type)` (interval ≠
   `none`) **and** the series is not ended, `next_due_by` is **required** (missing ⇒
   `{:error, :next_due_required}`) and a **new** Obligation is spawned with the same `series_id`,
   type, title, and assignees. Requiring next_due_by is deliberate — it stops a series from
   landing in a "no live cycle, not ended" limbo; to finish without a successor, **End series**.
   The 8 intervals live in `Obligations.Recurrence`; fixed intervals pre-fill the next `due_by`
   (`Recurrence.next_due_suggestion/2`), `custom` returns `nil` (blank picker), `none` is not
   recurring. Interval naming is deliberate: `every_two_weeks` (not bi_weekly), `semiannual`,
   `annual`. `shift_month/2` must clamp end-of-month (Jan 31 + 1mo → Feb 28).

3. **Corrections lock after Done/cancelled.** While a cycle is active: managers/admins edit
   obligation fields; note authors edit their own note within **48 hours** (manager/admin
   override anytime before Done). After Done/cancelled everything is locked except admin-only
   void-with-reason. Every correction is logged in `AuditLog`.

### Dashboard = the attention surface

There is intentionally **no notification system** (no bell, no email/SMS, no Oban). The
dashboard is where overdue/due-soon work surfaces, computed at render time:

- `Obligations.Urgency.classify(type, due_by, today)` → `:overdue | :due_soon | :ok`, where
  `:due_soon` means `due_by` is within any offset in the type's `reminder_offsets`
  (comma-delimited days, e.g. `"30,7,1"`). `today` is **required and computed in the entity's
  timezone** via `Urgency.today_for(entity.timezone)` — never `Date.utc_today()`, which would
  mis-date non-UTC tenants near midnight. Rendered by `UrgencyBadge` (red/amber/none).
- `reminder_offsets` / `complete_documents` are validated and normalized on the `Type` changeset
  (write time), so the render path can't crash on bad input; `parse_offsets` still parses defensively.
- Split view: **My work** (default for member) vs **Team overview** (default for manager/admin),
  filtered to **live cycles** (`status = active AND completed_at IS NULL`), sorted overdue →
  due_soon → `due_by` asc.

### Out of scope for v1

Subjects/client-asset linking (use the obligation title), in-app/email/SMS notifications,
Oban reminder jobs, REST API/mobile, billing beyond `plan`/`seat_limit` fields.

## Conventions

- **TDD per the plan:** write the failing test, watch it fail, implement, watch it pass, commit. One commit per task.
- **Context modules own domain logic.** LiveViews call `Argus.Obligations`, `Argus.Entities`, `Argus.Accounts` — not Repo directly.
- **Multi-step writes use `Ecto.Multi`/transactions** (create obligation + open event; Done + spawn next; cancel + event).
- File uploads (v1) go to the local filesystem under a **configurable** `:uploads_dir`
  (`config :argus, :uploads_dir`), laid out `:entity_id/:obligation_id/`; it defaults to the priv
  path in dev but must point at a persistent volume in prod (`:code.priv_dir` is not writable in a
  release). Reads are served by a scope-gated controller, never a static route.

## Deployment (Linode + Docker, peggy parity)

Argus ships the **same self-hosted Docker-on-Debian/Linode flow as peggy** (no Fly/Gigalixir).
A two-stage `Dockerfile` builds a Mix release; `mix release` picks up `rel/overlays/bin/server`
(boots with `PHX_SERVER=true`) and `rel/overlays/bin/migrate` (`./argus eval
Argus.Release.migrate`, which runs migrations without Mix inside the container). All
target-specific values live in **`deploy.conf`** (gitignored secrets stay out — `secret.txt`).

```bash
# First-time provision + deploy (prompts for server pwd, DB pwd, SMTP app-password;
# generates SECRET_KEY_BASE). Installs Docker/Nginx/Postgres 17, certbot, builds + ships image.
cd deploy_to_linode && ./launch.sh ../deploy.conf

# Subsequent deploys: rebuild image, stream to server, recreate container, run migrate.
./deploy.sh ../deploy.conf
```

- **`deploy.conf`** keys: `LINODE_IP`, `DB_NAME`/`DB_USER`, `DOCKER_HUB_USERNAME`, `IMAGE_NAME`,
  `DOCKER_CONTAINER_NAME`, `DOMAIN_NAME`, `PORT` (argus uses **8083** to avoid peggy's 8082 if
  co-located), `MAIL_HOST`/`MAIL_PORT`/`MAIL_USERNAME`/`MAIL_FROM`. Passwords + `SECRET_KEY_BASE`
  are prompted/generated at deploy time, never committed.
- **Prod runtime env** (baked into the container by the deploy scripts, read in `runtime.exs`):
  `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, and the SMTP `MAIL_*` vars — **all
  fail-loud** if missing. `:uploads_dir` is set to **`/uploads`**, the host volume
  (`/home/argus/uploads`) mounted into the container by `generate_files_at_server.sh`.
- **Mailer:** prod uses `Swoosh.Adapters.SMTP` (needs `gen_smtp`); the from-address comes from
  `config :argus, :mail_from` (Gmail wants an App Password, not the account password).
- `deploy_to_linode/` scripts are app-agnostic (parameterized by `deploy.conf`) and mirror
  peggy's — keep them in sync when peggy's deploy flow changes.
