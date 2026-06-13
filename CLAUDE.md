# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Argus is **greenfield**: the only files committed so far are the design spec and the
implementation plan under `docs/superpowers/`. The Phoenix app has **not been generated yet**.

- **Spec:** `docs/superpowers/specs/2026-06-13-argus-design.md` — authoritative for data model, roles, and workflows.
- **Plan:** `docs/superpowers/plans/2026-06-13-argus-implementation.md` — 19 phased, TDD, commit-per-task steps.

Execute the plan with `superpowers:subagent-driven-development` (or `executing-plans`).
Task 1 bootstraps the app with:

```bash
cd /home/tankwanghow/Projects/elixir
mix phx.new argus --binary-id --no-dashboard
# keep the mailer (magic-link login emails) and assets (Tailwind v4 + daisyUI)
# answer Y when it warns the argus/ dir already exists (it holds docs/)
```

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
mix deps.get                          # fetch deps (adds bcrypt_elixir, tzdata)
mix ecto.create && mix ecto.migrate   # set up DB
mix run priv/repo/seeds.exs           # seed system obligation-type presets (Malaysia regulatory)
mix phx.server                        # run app (localhost:4000)
mix test                              # full suite
mix test test/argus/obligations_test.exs            # single file
mix test test/argus/obligations_test.exs:42         # single test by line
```

Tech stack: Elixir 1.19 / OTP 28, Phoenix 1.8.5, LiveView 1.1, Ecto 3.13, PostgreSQL (citext), Tailwind v4 + daisyUI 5, Swoosh mailer (magic-link login), Req.

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
- `Argus.Entities` — entities, memberships `(user_id, entity_id, role)`, invitations. One default entity per user (partial unique index). `create_entity/2` also inserts the creator's `admin` membership.
- `Argus.Authorization` — `can?(user, action, entity)` / `can?(user, action, entity, obligation)`. Single source of truth for role rules; see the role table below. Unauthorized mutations return `:not_authorise`.

### Roles

| Role | Can |
|------|-----|
| admin | everything |
| manager | create/edit obligations, manage types, mark Done on **any** obligation, cancel, end series |
| member | view assigned work, add notes/docs while in progress, mark Done **only if primary assignee** |

Collaborators (join table) can move an obligation to `in_progress` and add notes/docs, but
**cannot** mark Done. Only the **primary assignee** or a manager/admin marks Done.

### Obligations domain — the core model (read the spec before editing)

The single most important design decision: **one `Obligation` row per cycle**, not a standing
series with a rolling `due_by`. A recurrence chain is linked by a shared `series_id` (UUID).

- `Argus.Obligations.Obligation` — one cycle. `status` is `active | cancelled`; **done-ness is a separate `completed_at` timestamp**, not a status value (a completed cycle keeps `status = active`). A cycle is **live** while `status = active AND completed_at IS NULL` — that's the set dashboards show and that can be worked/completed/cancelled. A partial unique index on `series_id` (where live) enforces **one live cycle per series**. `series_ended_at` (when set) blocks future spawning for the whole series.
- `Argus.Obligations.Event` (`obligation_events`) — **append-only forward-only** status steps: `open → in_progress → done | cancelled`. New status = new row; rows are never deleted and status is never rewritten. The step `note` lives here (open context, done comment, cancel reason).
- `Argus.Obligations.EventDocument` — file uploads attached to an event. Wrong files are **voided** (`voided_at`/`voided_by_id`/`void_reason`), never deleted. `document_slot` matches a name in the type's `complete_documents` for Done validation.
- `Argus.Obligations.AuditLog` — field-level before/after for **corrections** (title, due_by, assignee, note edits).
- `Argus.Obligations.Type` — system presets (`entity_id` NULL) + per-entity custom types.

### Three rules that are easy to get wrong

1. **Done validation is enforced only on Done**, never earlier. `complete_note_required` →
   note present on the Done event; `complete_documents` (comma-delimited slot names) → one
   **non-voided** document per named slot. See `Obligations.Completion`.

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
- File uploads (v1) go to the local filesystem under `priv/uploads/:entity_id/:obligation_id/`.
