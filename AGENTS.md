# SageBadger — Agent Instructions

> **Canonical context file:** See [claude.md](claude.md) for the full, detailed project instructions including tech stack, architecture, conventions, build status, code style preferences, and file locations.

## Quick Summary

SageBadger is an AI-powered contract tracker for SMBs built with Rails 8.1.2. Users upload contracts (PDF/DOCX/TXT), AI extracts structured data via the Anthropic Claude API, and the system generates automated alerts for expirations, renewals, and notice periods.

## Key Conventions

- **Framework**: Rails 8.1.2, Hotwire (Turbo + Stimulus), Tailwind CSS 4, PostgreSQL with UUID PKs
- **No SPA/React/Vue** — all interactivity is Hotwire-based
- **Service objects** in `app/services/` — business logic goes here, not in controllers or models
- **Multi-tenancy**: `acts_as_tenant(:organization)`, `Current.organization` holds the active tenant
- **Testing**: Minitest (not RSpec), run with `bin/rails test`
- **Background jobs**: Solid Queue, configured in `config/recurring.yml`
- **Auth**: Rails 8 built-in authentication, `Current.user` / `Current.session`
- **Billing**: Pay gem + Stripe, plan limits enforced via `PlanEnforcement` concern
- **Brand color**: amber-600

## Code Style

- Thin controllers, fat services
- Frozen constant arrays with inclusion validators for enum-like fields
- ERB views with Tailwind utility classes (no custom CSS unless necessary)
- `before_action` callbacks for setting instance variables
- `dom_id(record)` for Turbo Stream target IDs
- Turbo Streams for real-time updates from background jobs

## Commands

```bash
bin/rails test              # Run test suite
bin/rails test:system       # Run system tests
bin/rubocop                 # Lint
bin/brakeman --no-pager     # Security scan
bin/dev                     # Start dev server
```
