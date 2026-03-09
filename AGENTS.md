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

### Human verification / review pipeline

Every field the AI extracts goes through a review pipeline before it becomes canonical data.
The guiding principle is: **everything the system does should be explainable and purpose-driven**.
Every card shown to the user must explain *what* the AI found, *why* it needs attention, and *how* to resolve it.

#### Architecture overview

1. **AI extraction** (`ContractAiExtractorService`) extracts values + confidence scores per field.
2. **Orchestration** (`ContractReviewOrchestrationService`) creates `ContractReviewField` records and delegates to `FieldReadinessPolicy` for bucketing.
3. **Readiness engine** (`FieldReadinessPolicy`) scores each field into `blocked`, `needs_review`, or `looks_good`.
4. **Review UI** (`contract_reviews/_field.html.erb`) renders cards with explanations, form inputs, and action buttons.
5. **Completion** (`ContractReviewCompletionService`) validates all fields, applies canonical values, and activates.

#### Key files and their roles

| File | Role |
|------|------|
| `app/services/review_field_catalog.rb` | Single source of truth for tracked fields — classification, gating, dependencies, alert families, notes |
| `app/services/field_readiness_policy.rb` | Readiness bucketing engine — thresholds, structural checks, derived-field applicability |
| `app/services/contract_review_value_resolver.rb` | Type coercion + `DATE_FIELD_KEYS`, `INTEGER_FIELD_KEYS`, `DECIMAL_FIELD_KEYS` constants |
| `app/services/contract_review_completion_service.rb` | Validates + applies approved values on review completion |
| `app/services/contract_review_canonical_applier.rb` | Writes approved values to the actual contract/lease models |
| `app/helpers/application_helper.rb` | Explanation system, input type routing, select options, number constraints |
| `app/views/contract_reviews/_field.html.erb` | Field card partial — renders every review field |

#### Readiness engine details

- Thresholds use a 0–100 integer confidence scale, varying by field classification (`alert_driving`, `alert_governing`, `contextual`).
- Gating fields (`blocks_activation: true`) with nil confidence → `blocked`; non-gating → `needs_review`.
- Derived fields check applicability before structural checks (e.g., `recurrence_interval` is only applicable when sibling `recurring` is true).
- Confidence backfill: `backfill_missing_confidence!` in `ContractAiExtractorService` assigns a conservative 50 score (tagged `"confidence_backfilled"`) to direct fields where the AI omitted confidence.

#### Explanation system

`readiness_explanation(field, review:)` in `ApplicationHelper` is the single entry point for all card explanations. It dispatches to bucket-specific builders:
- `build_blocked_explanation` — explains why a field is locked (missing value, unresolved dependencies, etc.)
- `build_needs_review_explanation` — explains what the AI found and why human judgment is needed
- `build_looks_good_explanation` — confirms the AI is confident, with the specific threshold met

Cross-references use two mechanisms:
- `DEPENDENCY_CONTEXT_MAP` — maps a field_key to a sibling field_key for context (e.g., `recurrence_interval → recurring`). Shows the AI's reasoning chain with excerpts.
- `derived_dependency_summary(field, review)` — for derived fields, shows actual dependency values, confidence scores, and which ones still need approval.

#### Form input type system

`review_field_input_kind(field)` determines the HTML input rendered for each field, checked in this order:

1. `:select` — if field_key is in `FIELD_SELECT_OPTIONS` (dropdown with constrained values)
2. `:date` — if field_key is in `ContractReviewValueResolver::DATE_FIELD_KEYS`
3. `:boolean` — if `field_family == "alert_governing_boolean"`
4. `:number` — if field_key is in `INTEGER_FIELD_KEYS` or `DECIMAL_FIELD_KEYS`
5. `:text` — fallback for everything else

Supporting constants in `ApplicationHelper`:
- `FIELD_SELECT_OPTIONS` — maps field_key → array of valid values (sourced from model constants like `LeaseMilestone::RECURRENCE_INTERVALS`)
- `FIELD_NUMBER_CONSTRAINTS` — maps field_key → `{ min:, max:, step: }` for numeric inputs

#### How to add a new extracted field (checklist)

When adding a new field to the extraction + review pipeline, touch **all** of the following:

1. **Model validation** — add the attribute and any inclusion/format validations to the model (e.g., `Contract`, `LeaseDetail`, `LeaseMilestone`). If enum-like, define a frozen constant (e.g., `RECURRENCE_INTERVALS = %w[...].freeze`) and validate inclusion.

2. **Review Field Catalog** (`app/services/review_field_catalog.rb`) — add a `FieldDefinition` entry with:
   - `key:` — dotted field key (e.g., `"lease_milestone.recurrence_interval"`)
   - `classification:` — `"alert_driving"`, `"alert_governing"`, or `"contextual"`
   - `field_family:` — group name for related fields
   - `source_type:` — `"direct"` (AI-extracted), `"derived"` (calculated from other fields), or `"app_managed"`
   - `blocks_activation:` — `true` if this field must be resolved before contract activation
   - `lease_only:` — `true` if only relevant for lease-type contracts
   - `repeatable:` — `true` if field can have multiple indexed instances (milestones, escalations, options)
   - `dependencies:` — array of field_keys this field depends on (for derived fields)
   - `notes:` — **user-facing** business description shown in the explanation UI (not developer notes)

3. **AI extraction prompt** — the prompt's field reference is auto-generated from `ReviewFieldCatalog.review_prompt_field_groups`, so step 2 handles this. Verify the field appears in the generated prompt by checking `ReviewFieldCatalog.tracked_direct_fields`.

4. **Value resolver typing** (`app/services/contract_review_value_resolver.rb`) — add the field_key to the appropriate constant:
   - `DATE_FIELD_KEYS` for date fields
   - `INTEGER_FIELD_KEYS` for whole numbers
   - `DECIMAL_FIELD_KEYS` for monetary/percentage values
   - (Omit for strings — they're the default)

5. **Form input constraints** (`app/helpers/application_helper.rb`):
   - **If enum/constrained values**: add to `FIELD_SELECT_OPTIONS` mapping field_key → model constant or `[label, value]` pairs. This automatically renders a `<select>` dropdown.
   - **If numeric with bounds**: add to `FIELD_NUMBER_CONSTRAINTS` with `{ min:, max:, step: }`.
   - **If the field has a sibling that provides reasoning context**: add to `DEPENDENCY_CONTEXT_MAP` (e.g., `"lease_milestone.recurrence_interval" => "lease_milestone.recurring"`).

6. **Readiness applicability** (`app/services/field_readiness_policy.rb`) — if the field is conditionally applicable (e.g., only relevant when a sibling boolean is true), add a rule in `applicable?`.

7. **Canonical applier** (`app/services/contract_review_canonical_applier.rb`) — ensure the approved value is written to the correct model attribute on review completion.

8. **Tests** — add test coverage for:
   - Readiness bucketing (field_readiness_policy_test.rb)
   - Value resolution/coercion (contract_review_value_resolver_test.rb)
   - Completion with the new field (contract_review_completion_service_test.rb)

#### Common gotchas

- Ruby's `false.blank?` returns `true`. Value-presence checks must use `value.nil? || (value.is_a?(String) && value.blank?)`, never `.present?` or `.blank?` alone.
- When adding derived field relationships, update **both** `FieldReadinessPolicy.applicable?` and `DEPENDENCY_CONTEXT_MAP` in `ApplicationHelper`.
- Enum fields rendered as free text inputs will pass front-end validation but fail at `ContractReviewCanonicalApplier` with a cryptic "is not included in the list" error. Always add enum fields to `FIELD_SELECT_OPTIONS`.
- `derived_dependency_keys` on `ContractReviewField` is stored at creation time — changing catalog dependencies won't retroactively update existing reviews.
- Completion error messages are human-friendly: inclusion violations show valid options, not raw Rails validation output. This is handled in `ContractReviewCompletionService`.

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
