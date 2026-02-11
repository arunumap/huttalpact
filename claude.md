# SageBadger — Project Instructions for Claude

## Project Overview

SageBadger is an AI-powered contract tracker for SMBs built with Rails 8.1.2. The first target vertical is property management companies. The tagline is "Smart contract tracking that won't let you forget." The full build plan lives in `docs/BUILD_PLAN.md`.

## Tech Stack

- **Framework**: Rails 8.1.2 with Hotwire (Turbo + Stimulus), no React/Vue/SPA
- **Database**: PostgreSQL with UUID primary keys everywhere (via `pgcrypto` extension)
- **Assets**: Tailwind CSS 4 + Propshaft + Importmap (no Node.js/webpack/esbuild)
- **Background jobs**: Solid Queue (in-Puma for single-server)
- **Caching**: Solid Cache
- **WebSocket**: Solid Cable
- **File storage**: Active Storage (local dev, S3 planned for production)
- **AI**: Anthropic Claude API via `ruby-anthropic` gem
- **Auth**: Rails 8 built-in authentication generator (bcrypt, `has_secure_password`)
- **Multi-tenancy**: `acts_as_tenant` gem scoping on `Organization`
- **Pagination**: Pagy gem
- **Document parsing**: `pdf-reader` (PDF), `docx` (DOCX)
- **Deployment**: Kamal + Thruster + Docker (not yet deployed)

## Architecture & Conventions

### General Principles

- **Hotwire-first**: All interactivity uses Turbo Frames, Turbo Streams, and Stimulus controllers. Never introduce a JavaScript framework or SPA pattern.
- **Service objects**: Business logic belongs in `app/services/`, not in controllers or models. Controllers stay thin — they handle params, call services/jobs, and respond.
- **Background jobs**: Long-running work (text extraction, AI calls) goes through Solid Queue jobs in `app/jobs/`. Jobs broadcast Turbo Stream updates for real-time UI feedback.
- **No decorators or view components**: UI helpers live in `ApplicationHelper`. All views use ERB with Tailwind utility classes.

### Database

- All tables use UUID primary keys: `create_table :table_name, id: :uuid do |t|`
- All foreign keys must also be UUID: `t.references :parent, type: :uuid, null: false, foreign_key: true`
- Use `gen_random_uuid()` as the default (PostgreSQL's `pgcrypto` extension is enabled)
- Cascade deletes are used at the DB level for dependent records (e.g., contract_documents, key_clauses)

### Multi-Tenancy

- `acts_as_tenant(:organization)` is set on tenant-scoped models (Contract, Alert)
- `ApplicationController` sets the current tenant via `set_current_organization` before_action, using the current user's first organization membership
- `Current.organization` holds the active tenant
- There is currently no org-switching UI — users belong to one org

### Authentication

- Uses Rails 8 built-in `Authentication` concern (included in `ApplicationController`)
- `allow_unauthenticated_access` used on public controllers (sessions, registrations, passwords, pages, pricing)
- `Current.user` and `Current.session` are set via the Authentication concern
- Sessions are stored in a `sessions` table with `user_id`, `ip_address`, `user_agent`

### Models — Key Patterns

- Status/type values are defined as frozen constant arrays with inclusion validations (e.g., `STATUSES = %w[draft active expiring_soon expired renewed cancelled archived].freeze`)
- `Contract` has rich scopes: `active`, `expired`, `expiring_soon`, `inbound`, `outbound`, `search`, `by_type`, `by_status`, `expiring_within`, `renewal_within`
- `Contract` has a `direction` field: `"inbound"` (revenue) or `"outbound"` (expense)
- `ContractDocument` has callbacks: `after_create_commit :extract_text_later`, `after_destroy_commit :re_extract_contract`
- `ContractDocument` has `DOCUMENT_TYPES = %w[main_contract addendum amendment exhibit sow other].freeze`
- `Organization` includes `PlanLimits` concern — provides `at_contract_limit?`, `at_extraction_limit?`, `at_user_limit?`, `increment_extraction_count!`, Stripe price-to-plan mapping, extraction count tracking with monthly resets
- `Organization` has `pay_customer default_payment_processor: :stripe` for billing, `sync_plan_from_subscription!` for Stripe webhook sync, and `log_plan_change` for audit logging plan changes
- `KeyClause` links to both a `contract` and optionally a `source_document` (ContractDocument)

### Controllers

- All authenticated controllers inherit from `ApplicationController` which provides `require_authentication` and `set_current_organization`
- Use `before_action :set_contract` pattern for nested resources
- Respond with Turbo Streams where appropriate (document upload, extraction status, delete confirmations)
- Rate limiting is applied to auth endpoints (`rate_limit to:`)
- `BillingController` — Stripe checkout session creation, customer portal redirect, post-checkout success handling; restricted to org owners via `require_owner` before_action
- `PricingController` — Public-facing pricing page (allows unauthenticated access), uses a dedicated `pricing` layout
- `PagesController` — Public landing page at root (`pages#home`). Allows unauthenticated access, redirects authenticated users to `dashboard_path`. Uses `marketing` layout. Landing page has 6 sections: hero, features, how-it-works, testimonials, pricing teaser, final CTA
- `PlanEnforcement` concern (included in `ApplicationController`) — provides `enforce_contract_limit!` and `enforce_extraction_limit!` as before_actions on `ContractsController` (new/create) and `ContractExtractionsController`

### Views & UI

- **Brand color**: Amber/amber-600 is the primary brand color across buttons, links, badges, hover states, and accents
- **Layout**: `application.html.erb` has a fixed dark sidebar (w-64, slate-900) with navigation + a sticky top header bar + main content area
- **Auth layout**: `auth.html.erb` is a centered card layout for login/register/password reset
- **Marketing layout**: `marketing.html.erb` is the public landing page layout with SVG logo nav, Pricing/Sign In/Sign Up links, OG meta tags, and shared footer partial
- **Pricing layout**: `pricing.html.erb` is the public pricing page layout with SVG logo nav, conditional auth/unauth links, and shared footer partial
- **Shared footer**: `shared/_footer.html.erb` is used in both marketing and pricing layouts — SVG logo, tagline, Product links (Pricing, Sign Up, Sign In), Company links (About, Privacy, Terms), copyright
- **Partials**: Use `_partial.html.erb` naming. Turbo Stream targets use dom IDs like `dom_id(record)` or descriptive IDs like `"ai_extraction_status"`
- **Empty states**: All list views should have empty states with helpful messaging and a CTA
- **Flash messages**: Rendered in the layout with `notice` (green) and `alert` (red) styles
- **Badges**: Helper methods in `ApplicationHelper` generate styled badge spans for statuses, types, confidence scores, etc.
- **Icons**: Using inline SVG via the `inline_svg` gem. The badger logo is at `app/assets/images/badger_logo.svg`

### Services

- `ContractTextExtractorService` — Extracts raw text from PDF/DOCX/TXT files attached to a ContractDocument. 500K character truncation limit. Handles corrupt files, empty files, and encoding issues.
- `ContractAiExtractorService` — Sends extracted text to Claude (`claude-sonnet-4-20250514`, inline string) for structured extraction. 400K character input limit. Atomic reentrance guard (`UPDATE...WHERE extraction_status != 'processing'`). Enforces plan extraction limits. Supports two modes:
  - **Full mode**: First extraction or re-extract. Fills blank fields only (preserves user edits)
  - **Incremental mode**: When an addendum/amendment is uploaded to an already-extracted contract. Compares against prior AI output to preserve user edits and generates a `changes_summary`
  - Extensive output sanitization: validates/coerces enum values, dates, numerics, booleans, confidence scores; strips markdown fences from JSON; skips invalid key clauses; matches `source_document` filenames
- `AlertGeneratorService` — Generates alerts from contract dates (end_date, next_renewal_date, notice_period_days). Idempotent via clear-and-recreate for pending/snoozed alerts. Respects per-user AlertPreference settings for threshold days and channel preferences.
- `AlertDeliveryService` — Delivers due alerts to recipients via email (using AlertMailer) and in-app channels. Checks user preferences before sending.
- New services should follow the pattern: initialize with the primary record, expose a `call` method, return meaningful results

### Jobs

- `ExtractContractDocumentJob` — Extracts text from a single document, then chains `AiExtractContractJob` when ALL documents for a contract are done (uses locking to prevent race conditions)
- `AiExtractContractJob` — Runs AI extraction (full or incremental mode), broadcasts Turbo Stream updates. Retries 3x with polynomial backoff.
- `GenerateContractAlertsJob` — Runs AlertGeneratorService for a single contract. Triggered on contract create/update when date fields change.
- `DailyAlertCheckJob` — Recurring daily job (7am) that finds pending alerts due today or earlier and delivers them via AlertDeliveryService.
- `ContractStatusUpdaterJob` — Recurring daily job (midnight) that updates contract statuses: active → expired (end_date past), active → expiring_soon (end_date within 30 days).
- `ResetMonthlyExtractionsJob` — Recurring monthly job (1st of month at midnight) that resets `ai_extractions_count` for all organizations.
- `CleanStaleDraftsJob` — Recurring daily job (3am) that deletes draft contracts not updated in 7 days.
- Jobs broadcast Turbo Streams directly (e.g., `Turbo::StreamsChannel.broadcast_replace_to`) for real-time UI updates
- Recurring jobs are configured in `config/recurring.yml` (5 entries: `clear_solid_queue_finished_jobs` hourly, `daily_alert_check` 7am, `contract_status_updater` midnight, `reset_monthly_extractions` 1st of month, `clean_stale_drafts` 3am)

### Testing

- Uses Minitest (Rails default), not RSpec
- Test files exist in `test/controllers/`, `test/models/`, `test/services/`, `test/jobs/`
- Fixtures are in `test/fixtures/`
- `minitest-mock` gem is available for stubbing
- Run tests with `bin/rails test`

### Credentials

- Anthropic API key is stored in Rails encrypted credentials at `anthropic.api_key`
- Access with `Rails.application.credentials.anthropic_api_key` (note: uses underscore method delegation, i.e., `credentials.anthropic` returns the hash, `.api_key` reads the key)
- Postmark API token should be stored at `postmark.api_token` (required for production mailer config)
- Edit credentials with `EDITOR="code --wait" bin/rails credentials:edit`

## Current Build Status

### ✅ Completed

**Phase 1 — Foundation (Weeks 1–3):**
- Authentication (login, logout, registration, password reset)
- Multi-tenancy with `acts_as_tenant`
- App shell layout with dark sidebar and SageBadger branding
- Contract CRUD (index, show, new, create, edit, update, destroy)
- Search and filter (by title/vendor text, status dropdown, type dropdown)
- Pagination with Pagy
- ContractDocument model with Active Storage file attachments
- Drag-and-drop file upload (two Stimulus controllers: `file-upload` for new contracts, `document-upload` for existing contracts)
- ContractTextExtractorService (PDF, DOCX, plain text)
- ExtractContractDocumentJob with Turbo Stream status updates
- Extracted text preview on contract show page

**Phase 2 — AI Intelligence (Weeks 4–5):**
- Anthropic Claude API integration via `ruby-anthropic` gem
- ContractAiExtractorService with full + incremental extraction modes
- KeyClause model with 7 clause types and confidence scores
- Auto-populate contract fields from AI extraction
- Key clauses display with confidence badges and source document references
- Re-extract action on contract show page
- Rich dashboard: stat cards, upcoming renewals (30/60/90 day tabs), expiring contracts, status distribution, revenue/spend by type, top vendors, net cash flow, recently added contracts

**Beyond the original plan:**
- Multi-document extraction (addendums/amendments with incremental mode)
- Contract direction (inbound/outbound) with revenue vs. spend tracking
- Document type classification (main_contract, addendum, amendment, exhibit, sow, other)
- Incremental AI extraction that preserves user edits
- `last_changes_summary` field on contracts for incremental extraction audit trail

**Phase 3 — Alert System (Week 6):**
- Alert, AlertRecipient, AlertPreference models with UUID PKs and migrations
- AlertGeneratorService — idempotent clear-and-recreate for pending/snoozed alerts, generates `expiry_warning`, `renewal_upcoming`, `notice_period_start` based on contract dates and per-user preferences
- AlertDeliveryService — delivers alerts via email (Postmark) and in-app channels
- AlertMailer with HTML + text templates for alert notifications
- GenerateContractAlertsJob — triggered on contract create/update (when date fields change)
- DailyAlertCheckJob + ContractStatusUpdaterJob — recurring jobs in `config/recurring.yml`
- AlertsController with index (grouped by overdue/today/upcoming), acknowledge (Turbo Stream remove), snooze (1/3/7/14 day presets)
- AlertPreferencesController for per-user notification settings (email/in-app toggles, days_before_renewal, days_before_expiry)
- In-app notification bell dropdown in header with unread count badge
- Alerts sidebar navigation link
- Stimulus controllers: `notifications_controller.js` (bell dropdown), `snooze_dropdown_controller.js` (snooze presets)
- Helper badges: `alert_type_badge`, `alert_status_badge`, `alert_urgency_label`
- Email setup: `postmark-rails` for production, `letter_opener` for development
- Full test coverage: model, service, controller, job, and mailer tests (314 tests, 744 assertions, 0 failures)

**Phase 3 — Polish + UX (Week 7):**
- AuditLog model with 7 action types (created, updated, deleted, viewed, exported, alert_sent, plan_changed), acts_as_tenant scoped, UUID PKs
- Auditable controller concern — `log_audit(action, contract:, details:)` method included in ApplicationController with error rescue
- AuditLogsController with paginated index, action_type/contract_id filters
- Activity timeline on contract show page sidebar (last 10 entries, compact vertical timeline)
- Dedicated Activity Log index page with filter bar, table, pagination, empty state
- Audit hooks in ContractsController (create/view/update/delete), ContractDocumentsController (upload/delete), ContractExtractionsController (re-extract), AlertDeliveryService (alert_sent)
- Contract "archived" status — added to STATUSES, validation, scope, badge (purple), excluded from dashboard stats and expiring_within scope
- CSV export — `require "csv"` gem in Gemfile, `generate_csv` private method, `format.csv` in index action, Export CSV button in contracts header
- Bulk actions — `bulk_select_controller.js` Stimulus (select all, individual checkboxes, toolbar visibility, form submission with selected IDs), `bulk_archive` and `bulk_export` collection routes and controller actions, checkbox column + bulk toolbar in contracts index
- Flash messages — `flash_controller.js` Stimulus auto-dismiss (5s) + close button, icon-enhanced flash markup in both layouts (green checkmark for notice, red X for alert)
- Error handling — `rescue_from ActiveRecord::RecordNotFound` and `ActionController::ParameterMissing` in ApplicationController, redirects with flash for HTML, status codes for turbo_stream
- Loading states — `turbo-frame[busy]` opacity dimming CSS, `.turbo-progress-bar` amber, `data-turbo-submits-with` on submit buttons (contracts, alerts, registration, sign-in)
- Empty states — dashboard "Expiring Contracts" always shows card with conditional empty state
- Mobile responsive — `sidebar_controller.js` Stimulus (hamburger toggle + overlay, close on nav click), sidebar hidden on mobile with `-translate-x-full` + transition, hamburger button in header (lg:hidden), responsive padding (p-4 sm:p-6), `overflow-x-auto` on all tables, responsive stacking on contract index + show headers
- Bug fix: `expiring_within` and `renewal_within` scopes fixed (was `days.from_now`, now `days.days.from_now`)
- Full test coverage: 344 tests, 834 assertions, 0 failures

**Phase 4 — Billing (partial, Week 8):**
- Pay gem (~11.4) + Stripe (~18.0) integration — gems installed, `pay_customer` on Organization model
- `BillingController` — Stripe Checkout session creation, Customer Portal redirect, post-checkout success flow, owner-only access
- `PricingController` — public-facing pricing page with plan comparison, dedicated pricing layout
- `PlanLimits` concern on Organization — contract/extraction/user limits per plan, Stripe price-to-plan reverse mapping via ENV vars, extraction count tracking with monthly resets
- `PlanEnforcement` controller concern — `enforce_contract_limit!` on ContractsController (new/create), `enforce_extraction_limit!` on ContractExtractionsController
- `Organization#sync_plan_from_subscription!` — syncs plan tier from Stripe subscription status via Pay webhook callbacks
- `plan_changed` audit log action for plan change tracking
- Routes: `resource :pricing`, `resource :billing` (checkout/portal/success), `mount Pay::Engine`
- `ResetMonthlyExtractionsJob` — recurring 1st-of-month job to reset extraction counts

**Phase 4 — Launch (partial, Week 9):**
- Onboarding wizard for new users (organization details, first contract upload, invite teammate)
- Landing/marketing page:
  - `PagesController` at root route (`root "pages#home"`) — public landing page for unauthenticated visitors, redirects authenticated users to `dashboard_path`
  - Context-sensitive root: `root "pages#home"`, dashboard moved to `get "dashboard"` named route (`dashboard_path`). Sidebar and tests updated to use `dashboard_path` instead of `root_path`
  - `marketing` layout — SVG logo nav with Pricing/Sign In/Sign Up links, OG meta tags, flash messages, shared footer
  - Landing page sections: hero (tagline + CTAs), features grid (4 cards: AI extraction, automated alerts, key clause detection, dashboard), how-it-works (3 steps), testimonials (placeholder), pricing teaser (Free/Starter/Pro with link to full pricing), final CTA
  - `shared/_footer.html.erb` — reusable footer partial used in both marketing and pricing layouts (SVG logo, product links, company links, copyright)
  - `pricing` layout updated: SVG logo (replacing emoji), `dashboard_path` for authenticated links, shared footer partial included
  - Industry-agnostic copy — no vertical-specific language, suitable for any SMB
- SEO basics:
  - `SeoHelper` (`app/helpers/seo_helper.rb`) — renders meta description, canonical URL, robots directive, Open Graph tags, Twitter Card tags via `seo_meta_tags` method; JSON-LD structured data via `structured_data(type:)` for `:organization`, `:software_application`, `:faq`, `:breadcrumb`
  - All public layouts (`marketing`, `auth`, `pricing`) include `seo_meta_tags`
  - App-internal layouts (`application`, `onboarding`) set `noindex, nofollow` robots directive
  - Per-page SEO content on home, pricing, sign-in, and sign-up views via `content_for :title`, `:meta_description`, `:canonical_url`
  - Home page includes Organization + SoftwareApplication JSON-LD structured data
  - `robots.txt` updated with Allow/Disallow directives for public vs. authenticated routes
  - Full test coverage in `test/helpers/seo_helper_test.rb` (13 tests)
- Security audit:
  - Brakeman v8.0.2: 0 warnings (clean scan)
  - bundler-audit: 0 vulnerabilities (advisory DB updated 2026-02-07)

### ❌ Not Yet Started

**Phase 4 — Launch (Week 10):**
- Production deployment (Kamal configured but not deployed)
- S3 configuration for Active Storage
- Confirm Postmark API token is present in production credentials (gem + config done)
- Error tracking (Sentry or similar)
- Analytics (Plausible or similar)

## File Locations Quick Reference

| What | Where |
|---|---|
| Routes | `config/routes.rb` |
| Schema | `db/schema.rb` |
| Migrations | `db/migrate/` |
| Models | `app/models/` |
| Controllers | `app/controllers/` |
| Views | `app/views/` |
| Services | `app/services/` |
| Jobs | `app/jobs/` |
| Stimulus controllers | `app/javascript/controllers/` |
| Helpers | `app/helpers/application_helper.rb` |
| Layouts | `app/views/layouts/` |
| Tailwind entry | `app/assets/tailwind/application.css` |
| Importmap config | `config/importmap.rb` |
| Recurring jobs | `config/recurring.yml` |
| Credentials | `config/credentials.yml.enc` (edit with `EDITOR="code --wait" bin/rails credentials:edit`) |
| Build plan | `docs/BUILD_PLAN.md` |
| Tests | `test/` |
| Fixtures | `test/fixtures/` |

## Code Style & Preferences

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
