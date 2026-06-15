# Username + password onboarding for email-less members

**Date:** 2026-06-15
**Status:** Design — approved for planning
**Scope:** Identity & onboarding only. Roles, authorization, scope, entity routing, and the
obligations domain are untouched.

## Problem

Today the only identity is **email**. `users.email` is `citext NOT NULL UNIQUE`, and both login
paths (magic link and email+password) are email-keyed. The invitation-accept flow auto-registers a
user *by the invitation's email* and silently logs them in.

Many managers/members have **no email but do have a phone/device**. They need to (a) onboard via an
admin invite (emailed link **or** an on-screen QR code) and (b) **get back in after logging out**
without an email channel.

## Decisions (settled during brainstorming)

1. **Admins** keep registering with **email + magic link** — unchanged.
2. **Managers/members** are invited (email **or** QR) and, on first access, **choose a username +
   password**. They log back in with **username (or email) + password**.
3. **Username is globally unique** across all of argus (mirrors how email is unique). Login is a
   single lookup with no entity context; one account spans every entity the person joins.
4. **Returning users** (already have an account) join a second entity from the **same accept page**:
   logged-in → one-click Accept; logged-out → *Create account* **or** *Log in to accept*.
5. **Password recovery for username accounts = admin re-invite.** No self-service reset (there's no
   email channel). Admins keep email-based recovery.
6. **Phone / OTP is explicitly out of scope.** It buys nothing the chosen flow uses and carries a
   normalization dependency + an SMS/WhatsApp cost. `username` is the seam to add phone-OTP later as
   one coherent unit (column + delivery + reset together).

## Data model

### `users`
- **Add `username`** — `citext`, **nullable**, **globally unique** (unique index).
- **Relax `email` to nullable** — keep its existing unique index (Postgres treats multiple `NULL`s
  as distinct, so uniqueness still holds for the present ones).
- **Add a check constraint**: at least one of `email`, `username` is present — no identity-less user
  can exist.
- `hashed_password` already exists. It is **required for username accounts** (no email ⇒ no magic
  link; password is their only way in).

### `entity_invitations`
- **Relax `email` to nullable.** It becomes a **delivery + prefill convenience** (email it if
  present; otherwise the admin shows the link/QR). It is **no longer the user's identity** — the
  invitee picks their own username on accept.
- The "one pending invitation per email" unique constraint must become a **partial index** (only
  where `email IS NOT NULL`), so multiple email-less (QR) invitations can coexist.

## Schema/changeset changes

### `Argus.Accounts.User`
- `username_changeset/2` (or extend the registration changeset) — casts/validates `username`:
  format (e.g. `^[a-z0-9_]{3,30}$`, downcased via citext), uniqueness (`unsafe_validate_unique` +
  `unique_constraint`).
- A **registration-with-credentials changeset** that accepts `username` + `password` (+ optional
  `email`), validates "at least one identifier present", hashes the password, and is **confirmed
  immediately** (possession of the single-use invite token proves the invite was for them — same
  justification as magic-link confirmation).
- Keep `email_changeset` and `password_changeset` as-is for the existing email/admin paths.

### `Argus.Entities.Invitation`
- `changeset/2`: drop `email` from `validate_required` (keep `role`, `token`, `expires_at`); apply
  `validate_format(:email, ...)` **only when email is present**; scope the per-email unique
  constraint to the partial index name.

## Context API changes

### `Argus.Accounts`
- **`get_user_by_login_and_password/2`** — resolves the typed login against `email` **then**
  `username`, then verifies the password. This is the single resolver the password login uses.
  (Existing `get_user_by_email_and_password/2` may delegate to it or be replaced.)
- **`register_invited_user/1`** — creates a **confirmed** user from `%{username, password, email?}`
  for the *create-account* accept path. Replaces the implicit `get_or_register_invited_user/1`
  email-keyed auto-register for invited members (the old function may be retired once no caller
  needs silent email registration).

### `Argus.Entities`
- `invite_member/4` — allow a **nil/blank email** (QR invite); only call `UserNotifier` when an
  email is present. Signature otherwise unchanged.
- `accept_invitation/2` — **unchanged**; reused by all accept paths to attach the membership
  (seat-gated) once a `%User{}` exists.

## Onboarding / accept flow

`GET /invitations/:token` → `InvitationLive.Show` (prefetch-safe; **renders only, no side
effects**). Shows entity name + role, then branches on session state:

- **Already logged in** → single **Accept** button → `POST` with just the token →
  `accept_invitation/2` → redirect to `/entities/:slug`.
- **Logged out** → two forms:
  - **Create account** — `username` + `password` (+ optional `email`) → `register_invited_user/1`
    → `accept_invitation/2` → `log_in_user` → dashboard.
  - **Log in to accept** — `username-or-email` + `password` → `get_user_by_login_and_password/2`
    → `accept_invitation/2` → `log_in_user` → dashboard.

All three submit (via `phx-trigger-action`) to **`POST /invitations/:token/accept`**
(`InvitationController`), which pattern-matches on the params to pick the path. **GET stays
side-effect-free** so email/QR-scanner prefetches cannot register or log anyone in. Invalid/expired
token → flash + redirect home.

## Login changes

The existing password login form's email field becomes a **"Email or username"** field; its
controller path calls `get_user_by_login_and_password/2`. The **magic-link** form stays email-only
(it needs an inbox). Net: admins → email (magic or password); members → username (or email) +
password. Anti-enumeration behaviour (don't disclose which identifier is registered) is preserved.

## Recovery

- **Username/member accounts:** forgot password ⇒ **admin re-invite**. The admin re-issues the
  invite/QR from the Members screen; accepting it lets the user set a new password (matched to the
  existing account). No self-service reset.
- **Email/admin accounts:** unchanged (magic link / existing reset).

## Authorization, roles, scope — unchanged

No change to `Argus.Authorization`, the role table, `%Scope{}`, entity-scoped `live_session`
on-mounts, or Desktop/Mobile routing. This is purely an identity/onboarding change.

## Testing (TDD, house convention — failing test first, one commit per task)

- **Migration/schema:** `username` unique; `email` nullable; at-least-one-identifier check
  constraint rejects an empty user; invitation `email` nullable + partial pending-uniqueness.
- **Accounts:** `register_invited_user/1` creates a confirmed user from username+password; rejects
  duplicate username; `get_user_by_login_and_password/2` resolves by email and by username, rejects
  bad password, returns nil on unknown handle.
- **Entities:** `invite_member/4` succeeds with nil email (no `UserNotifier` call); still emails
  when email present.
- **InvitationController** (`POST .../accept`): create-account path (registers, confirms, joins,
  logs in, redirects); log-in-to-accept path (existing user joins, logs in); already-logged-in
  one-click; invalid token redirects home without a session.
- **InvitationLive.Show**: renders entity/role with **no side effects** (no user/membership
  created on view); shows the right forms per session state; logged-out shows both Create and Log
  in; logged-in shows one-click Accept.
- **Login**: password login succeeds with a username; existing email login still works.
- `mix precommit` green before declaring done.

## Out of scope (this change)

Phone identity, SMS/WhatsApp OTP login, member self-service email/OTP reset, passkeys. `username` is
the seam for a later phone-OTP unit (column + normalization + delivery + reset shipped together).
