# PactBadger — Agent Instructions (Canonical)

This is the canonical context file for AI agents working in this repo.
If anything here conflicts with the code, treat the code as the source of truth and update this file.

## Fast start

```bash
bin/setup
bin/dev

# One-shot local CI (setup + lint + security + tests)
bin/ci
```

## Commands (common)

```bash
bin/ci                      # Setup + RuboCop + security audits + tests (see config/ci.rb)
bin/rails test              # Minitest suite
bin/rubocop                 # Ruby lint
bin/brakeman --no-pager     # Security scan (bin/ci uses stricter flags)
bin/bundler-audit           # Gem vulnerability audit
bin/importmap audit         # JS dependency audit (Importmap)
bin/dev                     # Start dev server
```

Notes:
- `bin/ci` also runs `env RAILS_ENV=test bin/rails db:seed:replant`.
- System tests are currently optional/commented out in `config/ci.rb` (don’t assume `bin/rails test:system` exists in day-to-day flow).

## Source of truth (bookmark these)

- Routes/endpoints: `config/routes.rb`
- Data model: `db/schema.rb`
- Recurring jobs schedule (production): `config/recurring.yml`
- Environment differences: `config/environments/development.rb`, `config/environments/production.rb`, `config/environments/test.rb`

## Stack snapshot

- Rails 8.1.x, Hotwire (Turbo + Stimulus), Tailwind CSS, Importmap
- PostgreSQL with UUID PKs (generators default to UUID)
- Active Storage for uploads (local in development, S3 in production)
- AI extraction via Anthropic (see `ContractAiExtractorService` + `AiExtractionConfig`)
- Billing via Pay gem + Stripe (settings UI)
- Observability: Sentry configured (production only)

## Architecture map (where to look / add code)

### Multi-tenancy + current organization

- Tenant is set per-request in `ApplicationController` and stored in `Current.organization`.
- Organization switching exists (session-backed): `OrganizationSwitchesController#create` and `post "switch_organization/:id"` route.
- Key entry points: `app/controllers/application_controller.rb`, `app/controllers/organization_switches_controller.rb`.

Gotcha: background jobs do not automatically have `Current.organization`; jobs should load records by id and rely on `acts_as_tenant` scoping where applicable.

### Contracts, documents, and extraction pipeline

- Primary model: `app/models/contract.rb` (also hosts lease-related associations).
- Uploaded documents: `app/models/contract_document.rb`.
- Text extraction job: `app/jobs/extract_contract_document_job.rb`.
- AI extraction job: `app/jobs/ai_extract_contract_job.rb`.
- AI extraction service: `app/services/contract_ai_extractor_service.rb`.

Behavior:
- `ContractDocument` enqueues text extraction on create (`after_create_commit :enqueue_extraction`).
- When all docs are extracted, the pipeline enqueues AI extraction; incremental mode is used when AI data already exists.

### AI extraction configuration (admin-managed)

- Extraction configs live in DB: `app/models/ai_extraction_config.rb`.
- Service chooses a config via `AiExtractionConfig.active_for(...)`.
- Admin UI: `app/controllers/admin/ai_extraction_configs_controller.rb` and `admin` routes.

### Alerts

- Alert types and user visibility are defined in `app/models/alert.rb`.
- Alert generation is centralized in `app/services/alert_generator_service.rb`.
- Recurring delivery/maintenance jobs are scheduled in `config/recurring.yml`.

### Review learning operations loop

- Data ingestion happens when reviews are completed (`ReviewLearningIngestionService`), but production also runs a daily refresh via `RefreshReviewLearningOpsLoopJob` (scheduled in `config/recurring.yml`) to keep aggregate and recommendation snapshots current.
- Manual backfill/refresh command: `bin/rails "review_learning:refresh"` (optional args: `as_of_date`, `aggregate_lookback_days`, `organization_id`).
- Review workflow:
  1. Refresh aggregates/recommendations (automatic nightly or manual command).
  2. Review `Admin > Review Learning` metrics (volume, correction/error rate, calibration gap, worst fields).
  3. Decide whether to adjust model/prompt config (`Admin > AI Extraction Configs`) or threshold strategy.
  4. Apply changes manually and re-check metrics after additional review outcomes.
- Safety default: recommendation data is advisory; the app does not auto-apply threshold/model/prompt changes.

### Billing + plan enforcement

- Plan limits: `app/models/concerns/plan_limits.rb`.
- Billing UI/controller: `app/controllers/settings/billing_controller.rb`.
- Subscription orchestration and Stripe lookup: `app/services/subscription_manager_service.rb`, `app/services/stripe_price_resolver.rb`.

### Admin area

- Admin namespace is defined in `config/routes.rb`.
- Controllers live in `app/controllers/admin/` (AI usage, extraction configs, jobs dashboard, billing tooling, etc.).

## Conventions (how to make changes safely)

- Hotwire-first: use Turbo Frames/Streams + Stimulus; do not introduce a SPA framework.
- Keep controllers thin; put business logic in service objects under `app/services/`.
- Prefer frozen constant arrays + inclusion validations for enum-like fields.
- Use Turbo Stream broadcasts from jobs for live UI updates when appropriate.

## Environment reality (important)

- Development does not configure Solid Queue/Solid Cache adapters explicitly; production does.
	- Production sets `config.active_job.queue_adapter = :solid_queue` and `config.cache_store = :solid_cache_store`.
- Recurring jobs in `config/recurring.yml` are production-scoped.
- Sentry is enabled only in production (`config/initializers/sentry.rb`).
