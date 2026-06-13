---
name: argus-conventions
description: House conventions for building Argus — use whenever implementing or reviewing Argus code (contexts, schemas, auth/onboarding, LiveViews, Desktop/Mobile UI, CSS). Mirrors the sibling Phoenix projects in ~/Projects/elixir, primarily peggy (UI, onboarding, scope) and full_circle (contexts, authorization).
---

# Argus House Conventions

Argus follows the conventions of the user's other Phoenix 1.8 / LiveView 1.1 apps in
`~/Projects/elixir`. **peggy** is the primary reference for UI, onboarding, and request scope;
**full_circle** for context/authorization shape. When in doubt, open the corresponding peggy file
and match it. Peggy's full Phoenix 1.8 ruleset lives in `~/Projects/elixir/peggy/AGENTS.md` — its
rules apply to Argus too.

## Stack

- Elixir 1.19 / OTP 28, Phoenix 1.8.5, LiveView 1.1, Ecto 3.13, PostgreSQL (citext).
- **Tailwind v4 + daisyUI 5.** No `tailwind.config.js`; use `@import "tailwindcss"` + `@source`
  directives in `app.css`. Never `@apply`. Build UI from daisyUI classes (`btn`, `card`, `badge`,
  `modal`, `navbar`, `alert`, `input`, `fieldset`, …) and the shared `core_components.ex` /
  `layouts.ex` — don't hand-roll equivalents. This means the app is generated **with assets**
  (do NOT pass `--no-assets` to `mix phx.new`).
- Only `app.js` / `app.css` bundles. Vendor deps import into those. Never reference external
  `src`/`href` in layouts; never inline `<script>` — use colocated hooks
  (`:type={Phoenix.LiveView.ColocatedHook}`).
- HTTP: `Req` only.

## Schema & contexts

- `use Argus.Schema` (binary_id PK, `@foreign_key_type :binary_id`). Mirrors `FullCircle.Schema`.
  Argus additionally sets `@timestamps_opts [type: :utc_datetime]` (the spec uses utc_datetime
  throughout) — this is the one intentional divergence from full_circle's naive default.
- Domain logic lives in context modules (`Argus.Accounts`, `Argus.Entities`, `Argus.Obligations`).
  LiveViews call contexts, never `Repo` directly.
- **Bespoke context functions** (decided): `create_obligation/3`, `complete/4`, etc. — Argus does
  NOT adopt full_circle's generic `StdInterface`.
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

Argus uses Phoenix 1.8 `phx.gen.auth` **magic-link / passwordless-first** onboarding, exactly like
peggy — not a password form. (A password can still be added later in settings; the *primary*
onboarding path is email + login link.)

- **Onboarding flow:**
  1. Register with **email only** (`UserLive.Registration` collects just email; `<.input
     type="email">`).
  2. `Accounts.register_user/1` then `Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))`
     emails a login link.
  3. `UserLive.Confirmation` (the `/users/log-in/:token` view) confirms the account and logs in
     ("Confirm and stay logged in" vs "only this time" → remember-me).
  4. After sign-in, user lands on entity selection / creation; first entity they create becomes
     their default membership (admin).
- **Scope struct** — `Argus.Accounts.Scope` (mirror `Peggy.Accounts.Scope`):
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
- Authorization is `Argus.Authorization.can?(user_or_scope, :action, entity)` — pattern-matched
  clauses (mirror `FullCircle.Authorization`) with an `allow_roles(~w(admin manager), entity, user)`
  helper. Roles: `admin | manager | member`.

## Dual interface — Desktop + Mobile (peggy model)

Two UIs share the same contexts/schemas, each with its own LiveViews and layout:

- **Desktop** under `/entities/:entity_slug/...` — `ArgusWeb.EntityLive.*` / `ObligationLive.*` /
  `DashboardLive.*`. Top `navbar` via `Layouts.app/1`. Wider layouts (`mx-auto max-w-5xl`),
  responsive padding (`px-4 sm:px-6 lg:px-8`).
- **Mobile** under `/m/:entity_slug/...` — `ArgusWeb.MobileLive.*`. `Layouts.mobile_app/1` shell:
  `min-h-screen bg-base-100 pb-20`, a fixed bottom tab nav (`mobile_bottom_nav`, grid of 3–4
  tabs with `hero-*` icons, `pb-[env(safe-area-inset-bottom)]`), and a "More" sheet for
  theme/switch-entity/log-out. Large touch targets, sticky page header with search.
- **`AutoRouteByDevice` plug** (mirror peggy's) in the authed pipeline: redirects `/entities/<slug>`
  → `/m/<slug>` for mobile UAs and vice-versa, honoring a `argus_view=mobile|desktop` cookie set by
  explicit Mobile/Desktop toggle links. Only redirect when the counterpart route exists (whitelist
  of mobile-capable tails) so single-UI pages never 404.
- Every template begins with `<Layouts.app flash={@flash} current_scope={@current_scope}>` (desktop)
  or `<Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>` (mobile).
  `<.flash_group>` is only ever called inside `layouts.ex`.

## LiveView idioms

- `use ArgusWeb, :live_view`; the `:app` layout is set in the `use` macro (web.ex), as in
  full_circle.
- **Forms:** always `to_form/2` in the LiveView + `<.form for={@form}>` + `<.input>` in the
  template. Never pass a changeset to `<.form>`. Override input classes fully if you override at all.
- **Icons:** always `<.icon name="hero-..." />`; never the `Heroicons` module.
- **Collections:** Phoenix **streams** (`stream/3` + `phx-update="stream"`); never
  `phx-update="append"`. Index lists use `@per_page 30` + infinite scroll
  (`phx-viewport-bottom`, an `infinite_scroll_footer`, `@end_of_timeline?`) and an
  `IndexComponent` `live_component` per row (full_circle pattern).
- Gettext on **all** user-facing text — `gettext("...")` / `{gettext(...)}`. Locale in session
  (`set_locale`); English default, structured for more locales.
- Rebind block results (`socket = if connected?(...) do ... end`); no `String.to_atom/1` on user
  input; predicates end in `?`; `Enum.at` not `list[i]`; direct field access on structs (no
  `struct[:field]`).

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
