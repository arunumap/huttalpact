# PactBadger

**Smart contract tracking that won't let you forget.**

PactBadger is an AI-powered contract tracker for SMBs. Upload contracts (PDF, DOCX, or TXT), and AI automatically extracts key dates, values, clauses, and vendor information. The system then generates automated alerts for expirations, renewals, and notice periods — so you never miss a deadline again.

First target vertical: property management companies (5–50 properties).

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Rails 8.1.2 with Hotwire (Turbo + Stimulus) |
| Database | PostgreSQL with UUID primary keys |
| Frontend | Tailwind CSS 4 + Propshaft + Importmap (no Node.js) |
| Background Jobs | Solid Queue (in-Puma) |
| AI | Anthropic Claude API via `ruby-anthropic` gem |
| Auth | Rails 8 built-in authentication |
| Multi-tenancy | `acts_as_tenant` scoped on Organization |
| Billing | Pay gem + Stripe |
| File Storage | Active Storage (local dev, S3 planned for prod) |
| Email | Postmark (production), Letter Opener (development) |
| Deployment | Kamal + Thruster + Docker |

## Prerequisites

- **Ruby** 3.4.8 (see `.ruby-version`)
- **PostgreSQL** 14+
- **Bundler** 2.x

## Setup

```bash
# Clone the repo and install dependencies
git clone <repo-url> && cd pactbadger
bin/setup

# Configure credentials (Anthropic API key, Stripe keys, etc.)
EDITOR="code --wait" bin/rails credentials:edit
```

Required credential keys:

```yaml
anthropic:
  api_key: sk-ant-...
postmark:
  api_token: ...
```

### Stripe Setup

Stripe prices are resolved at runtime via **lookup keys** — no price ID env vars needed.
Set up your Stripe products and prices with the rake task:

```bash
bin/rails stripe:setup
```

This creates two products (Starter, Pro) with four prices using lookup keys:
`starter_monthly`, `starter_annual`, `pro_monthly`, `pro_annual`.

If you prefer manual setup, create prices in the Stripe Dashboard and assign
the same lookup keys. See `lib/tasks/stripe.rake` for details.

## Development

```bash
# Start the dev server (Rails + Tailwind watcher)
bin/dev

# Or run Rails server alone
bin/rails server

# Start Solid Queue workers
bin/jobs
```

The app runs at `http://localhost:3000`.

Recurring jobs are configured in [config/recurring.yml](config/recurring.yml) (production scope by default).

## Testing

```bash
# Run the full test suite
bin/rails test

# Run system tests (requires Chrome/Selenium)
bin/rails test:system

# Run a specific test file
bin/rails test test/models/contract_test.rb

# Linting
bin/rubocop

# Security scans
bin/brakeman --no-pager
bin/bundler-audit
```

## Architecture

- **Service objects** in `app/services/` — business logic lives here, not in controllers or models
- **Background jobs** in `app/jobs/` — text extraction, AI calls, alert delivery all run async via Solid Queue
- **Multi-tenancy** — all tenant-scoped models use `acts_as_tenant(:organization)`; `Current.organization` holds the active tenant
- **AI extraction** — `ContractAiExtractorService` sends document text to Claude for structured field extraction with full and incremental modes
- **Alerts** — `AlertGeneratorService` creates alerts from contract dates; `DailyAlertCheckJob` delivers them on schedule

See [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) for the full product plan. The database schema in [db/schema.rb](db/schema.rb) is the source of truth for the data model.

For AI agent context (Claude Code, Codex, etc.), see [claude.md](claude.md) and [AGENTS.md](AGENTS.md).
