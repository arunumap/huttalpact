# PactBadger — Agent Context (Legacy Pointer)

This repo’s canonical agent context lives in **AGENTS.md**.
This file is intentionally kept short to avoid drift.

## Start here

- Canonical agent instructions: `AGENTS.md`
- One-shot local CI (lint + security + tests): `bin/ci` (see `config/ci.rb`)

## Source of truth

When in doubt, prefer these over any summary doc:

- Routes: `config/routes.rb`
- Schema: `db/schema.rb`
- Recurring jobs (production): `config/recurring.yml`
- Env-specific behavior: `config/environments/*.rb`

## Implementation expectations (high-level)

- Hotwire-first (Turbo + Stimulus); no SPA frameworks.
- Keep controllers thin; put business logic in `app/services/`.
- Prefer constants + inclusion validations for enum-like fields.

If you find inaccuracies or missing context while working, update `AGENTS.md` as part of the change.

- Follow Rails conventions and the existing patterns in the codebase
- Use Tailwind utility classes directly in ERB — no custom CSS classes unless absolutely necessary
- Use amber-600 as the brand/accent color
- Keep controllers thin; extract logic to services
- Use Turbo Streams for real-time updates from background jobs
- Use Stimulus for client-side interactivity (drag-and-drop, tabs, toggles)
- Validate with frozen constant arrays + inclusion validators for enum-like fields
- Use scopes on models for common queries
- Write Minitest tests for new code
- Use `Current.user` and `Current.organization` for accessing the authenticated context
- Prefer `before_action` callbacks for setting instance variables in controllers
- Use `dom_id(record)` for Turbo Stream target IDs
