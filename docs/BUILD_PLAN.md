# HuttalPact — MVP Build Plan

> **Product**: AI-powered contract tracker for SMBs
> **Tagline**: Smart contract tracking that won't let you forget
> **First vertical**: Property management companies
> **Strategy**: Build horizontal, market vertical

---

## Tech Stack

- **Framework**: Rails 8.1.2 (Hotwire / Turbo / Stimulus)
- **Database**: PostgreSQL with UUID primary keys (pgcrypto)
- **Assets**: Tailwind CSS 4 + Propshaft + Importmap
- **Background jobs**: Solid Queue (in-Puma for single-server)
- **Caching**: Solid Cache
- **WebSocket**: Solid Cable
- **File storage**: Active Storage (local dev, S3 production)
- **AI**: Anthropic Claude API (contract extraction)
- **Auth**: Rails 8 built-in authentication generator
- **Multi-tenancy**: acts_as_tenant
- **Payments**: Pay gem + Stripe
- **Email**: Postmark (letter_opener in development)
- **Deployment**: Kamal + Thruster + Docker

---

## Pricing Tiers

| Tier | Price | Contracts | AI Extractions | Users | Audit Log |
|------|-------|-----------|----------------|-------|-----------|
| Free | $0/mo | 10 | 5/mo | 1 | 7 days |
| Starter | $49/mo | 100 | 50/mo | 5 | 30 days |
| Pro | $149/mo | Unlimited | Unlimited | Unlimited | Unlimited |

---

## Data Model (14 Models)

All tables use UUID primary keys and UUID foreign keys.

### Core Models

```ruby
# Organization (tenant)
create_table :organizations, id: :uuid do |t|
  t.string :name, null: false
  t.string :slug, null: false, index: { unique: true }
  t.string :plan, default: "free"  # free, starter, pro
  t.integer :contracts_count, default: 0
  t.integer :ai_extractions_count, default: 0
  t.datetime :ai_extractions_reset_at
  t.integer :onboarding_step, default: 0
  t.datetime :onboarding_completed_at
  t.timestamps
end

# User
create_table :users, id: :uuid do |t|
  t.string :email_address, null: false, index: { unique: true }
  t.string :password_digest, null: false
  t.string :first_name
  t.string :last_name
  t.timestamps
end

# Session (Rails 8 authentication)
create_table :sessions, id: :uuid do |t|
  t.references :user, null: false, foreign_key: true, type: :uuid
  t.string :ip_address
  t.string :user_agent
  t.timestamps
end

# Membership (join table: users <-> organizations)
create_table :memberships, id: :uuid do |t|
  t.references :user, null: false, foreign_key: true, type: :uuid
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.string :role, default: "member"  # owner, admin, member
  t.timestamps
  t.index [:user_id, :organization_id], unique: true
end

# Invitation (token-based team invites)
create_table :invitations, id: :uuid do |t|
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.references :inviter, null: false, foreign_key: { to_table: :users }, type: :uuid
  t.string :email, null: false
  t.string :token, null: false, index: { unique: true }
  t.string :role, default: "member"
  t.datetime :expires_at
  t.datetime :accepted_at
  t.timestamps
  t.index [:organization_id, :email]
  t.index [:organization_id, :accepted_at]
end

# Contract (core entity)
create_table :contracts, id: :uuid do |t|
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.string :title, null: false
  t.string :vendor_name
  t.string :status, default: "active"  # draft, active, expiring_soon, expired, renewed, cancelled, archived
  t.string :contract_type  # lease, service_agreement, maintenance, insurance, software, other
  t.string :direction, default: "outbound"  # inbound (revenue), outbound (expense)
  t.date :start_date
  t.date :end_date
  t.date :next_renewal_date
  t.integer :notice_period_days
  t.decimal :monthly_value, precision: 10, scale: 2
  t.decimal :total_value, precision: 12, scale: 2
  t.boolean :auto_renews, default: false
  t.string :renewal_term  # month-to-month, annual, 2-year, custom
  t.text :notes
  t.text :ai_extracted_data  # JSON blob of all AI-extracted fields
  t.text :last_changes_summary  # summary of what changed in incremental extraction
  t.string :extraction_status, default: "pending"  # pending, processing, completed, failed
  t.references :uploaded_by, foreign_key: { to_table: :users }, type: :uuid
  t.timestamps
end

# ContractDocument (Active Storage metadata + extracted text)
create_table :contract_documents, id: :uuid do |t|
  t.references :contract, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
  t.text :extracted_text
  t.string :extraction_status, default: "pending"  # pending, processing, completed, failed
  t.string :document_type, default: "main_contract"  # main_contract, addendum, amendment, exhibit, sow, other
  t.integer :position, default: 0
  t.integer :page_count
  t.timestamps
end

# KeyClause (extracted clauses from AI)
create_table :key_clauses, id: :uuid do |t|
  t.references :contract, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
  t.references :source_document, foreign_key: { to_table: :contract_documents, on_delete: :cascade }, type: :uuid
  t.string :clause_type  # termination, renewal, penalty, sla, price_escalation, liability, insurance_requirement
  t.text :content
  t.string :page_reference
  t.integer :confidence_score  # 0-100
  t.timestamps
end

# Alert
create_table :alerts, id: :uuid do |t|
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.references :contract, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
  t.string :alert_type  # renewal_upcoming, expiry_warning, notice_period_start
  t.date :trigger_date
  t.string :status, default: "pending"  # pending, sent, acknowledged, snoozed, cancelled
  t.text :message
  t.timestamps
end

# AlertRecipient
create_table :alert_recipients, id: :uuid do |t|
  t.references :alert, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
  t.references :user, null: false, foreign_key: true, type: :uuid
  t.string :channel, default: "email"  # email, in_app
  t.datetime :sent_at
  t.datetime :read_at
  t.date :snoozed_until
  t.timestamps
  t.index [:alert_id, :user_id], unique: true
end

# AlertPreference (per-user notification settings)
create_table :alert_preferences, id: :uuid do |t|
  t.references :user, null: false, foreign_key: true, type: :uuid
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.boolean :email_enabled, default: true
  t.boolean :in_app_enabled, default: true
  t.integer :days_before_renewal, default: 30
  t.integer :days_before_expiry, default: 14
  t.timestamps
  t.index [:user_id, :organization_id], unique: true
end

# AuditLog
create_table :audit_logs, id: :uuid do |t|
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.references :user, foreign_key: true, type: :uuid
  t.references :contract, foreign_key: { on_delete: :nullify }, type: :uuid
  t.string :action  # created, updated, deleted, viewed, exported, alert_sent, alert_acknowledged, alert_snoozed, plan_changed
  t.text :details
  t.timestamps
end
```

---

## Model Associations

```ruby
class Organization < ApplicationRecord
  include PlanLimits

  pay_customer default_payment_processor: :stripe

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :contracts, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :alert_preferences, dependent: :destroy
  has_many :invitations, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true
  validates :plan, inclusion: { in: %w[free starter pro] }
end

class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :alert_recipients, dependent: :destroy
  has_many :alerts, through: :alert_recipients
  has_many :alert_preferences, dependent: :destroy
  has_many :audit_logs
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end

class Membership < ApplicationRecord
  ROLES = %w[owner admin member].freeze

  belongs_to :user
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }
end

class Invitation < ApplicationRecord
  belongs_to :organization
  belongs_to :inviter, class_name: "User"

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: Membership::ROLES }
  validates :token, presence: true, uniqueness: true

  scope :pending, -> { where(accepted_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }
end

class Contract < ApplicationRecord
  acts_as_tenant :organization
  belongs_to :organization, counter_cache: true
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_many :contract_documents, dependent: :destroy
  has_many :key_clauses, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  STATUSES = %w[draft active expiring_soon expired renewed cancelled archived].freeze
  CONTRACT_TYPES = %w[lease service_agreement maintenance insurance software other].freeze
  DIRECTIONS = %w[inbound outbound].freeze
  RENEWAL_TERMS = %w[month-to-month annual 2-year custom].freeze

  validates :title, presence: true, unless: :draft?
  validates :status, inclusion: { in: STATUSES }
  validates :direction, inclusion: { in: DIRECTIONS }
end

class ContractDocument < ApplicationRecord
  belongs_to :contract
  has_many :key_clauses, foreign_key: :source_document_id, dependent: :destroy
  has_one_attached :file

  DOCUMENT_TYPES = %w[main_contract addendum amendment exhibit sow other].freeze
  ALLOWED_CONTENT_TYPES = %w[application/pdf application/vnd.openxmlformats-officedocument.wordprocessingml.document text/plain].freeze
  MAX_FILE_SIZE = 25.megabytes
end

class KeyClause < ApplicationRecord
  belongs_to :contract
  belongs_to :contract_document, foreign_key: :source_document_id, optional: true

  CLAUSE_TYPES = %w[termination renewal penalty sla price_escalation liability insurance_requirement].freeze

  validates :clause_type, presence: true, inclusion: { in: CLAUSE_TYPES }
  validates :content, presence: true

  scope :high_confidence, -> { where("confidence_score >= 80") }
end

class Alert < ApplicationRecord
  acts_as_tenant :organization
  belongs_to :organization
  belongs_to :contract
  has_many :alert_recipients, dependent: :destroy

  ALERT_TYPES = %w[renewal_upcoming expiry_warning notice_period_start].freeze
  STATUSES = %w[pending sent acknowledged snoozed cancelled].freeze

  scope :pending, -> { where(status: "pending") }
  scope :due_today, -> { where(trigger_date: Date.current) }
  scope :due_on_or_before, ->(date) { where(trigger_date: ..date) }
end

class AlertRecipient < ApplicationRecord
  belongs_to :alert
  belongs_to :user

  CHANNELS = %w[email in_app].freeze

  scope :unread, -> { where(read_at: nil) }
  scope :unsent, -> { where(sent_at: nil) }
  scope :not_snoozed, -> { where("snoozed_until IS NULL OR snoozed_until <= ?", Date.current) }
end

class AlertPreference < ApplicationRecord
  acts_as_tenant :organization
  belongs_to :user
  belongs_to :organization

  validates :user_id, uniqueness: { scope: :organization_id }
end

class AuditLog < ApplicationRecord
  acts_as_tenant :organization
  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :contract, optional: true

  ACTIONS = %w[created updated deleted viewed exported alert_sent alert_acknowledged alert_snoozed plan_changed].freeze

  scope :recent, -> { order(created_at: :desc) }
  scope :for_contract, ->(contract) { where(contract: contract) }
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :organization

  delegate :user, to: :session, allow_nil: true
end
```

### Model Concerns

```ruby
# app/models/concerns/plan_limits.rb
module PlanLimits
  PLAN_LIMITS = {
    "free"    => { contracts: 10,              extractions: 5,                users: 1,                audit_log_days: 7   },
    "starter" => { contracts: 100,             extractions: 50,              users: 5,                audit_log_days: 30  },
    "pro"     => { contracts: Float::INFINITY, extractions: Float::INFINITY, users: Float::INFINITY,  audit_log_days: nil }
  }.freeze

  # Methods: plan_contract_limit, plan_extraction_limit, plan_user_limit
  # at_contract_limit?, at_extraction_limit?, at_user_limit?
  # contracts_remaining, extractions_remaining
  # increment_extraction_count!, reset_monthly_extractions!
  # sync_plan_from_subscription! (reads Pay subscription, maps Stripe price_id -> plan)
end
```

---

## Service Objects

### ContractTextExtractorService

Extracts raw text from uploaded PDF/DOCX/TXT files. Handles corrupt files, empty files, and invalid encoding. Truncates text at 500K chars.

```ruby
class ContractTextExtractorService
  def initialize(contract_document)
    @document = contract_document
  end

  def call
    # Detects content type, extracts text via:
    #   PDF  -> PDF::Reader (with page count)
    #   DOCX -> Docx gem + Nokogiri (tables, headers/footers via raw XML)
    #   TXT  -> direct download with UTF-8 encoding
    # Updates document extraction_status and extracted_text
  end
end
```

### ContractAiExtractorService

Sends extracted text to Claude for structured data extraction. Supports full and incremental modes.

```ruby
class ContractAiExtractorService
  # Full mode: extracts from all documents, only fills blank contract fields
  # Incremental mode: re-analyzes with prior extraction, overwrites only AI-changed values (preserves user edits)
  # Reentrance guard: uses atomic UPDATE WHERE extraction_status != 'processing'
  # Extraction limit: checks org limit before API call, raises ExtractionLimitReachedError
  # Sanitization: validates enums, dates, numerics, booleans, confidence scores before persisting
  # Multi-document: labels each document with filename + type in prompt
  # Text truncation: proportional truncation across documents at 400K char limit
  # Key clauses: tracks source_document_id per clause

  def initialize(contract, mode: :full, new_document_id: nil)
  end

  def call
    # 1. Check extraction limit
    # 2. Build labeled document text
    # 3. Send to Claude (claude-sonnet-4-20250514)
    # 4. Parse JSON (handles markdown-wrapped responses)
    # 5. Sanitize extracted data
    # 6. Apply to contract (full or incremental)
    # 7. Recreate key clauses
    # 8. Increment extraction count
  end
end
```

### ContractDraftCreatorService

Creates draft contracts from file uploads (upload-first flow).

```ruby
class ContractDraftCreatorService
  def initialize(user:, organization:, files:)
  end

  def call
    # Creates a draft contract with "Untitled Draft" title
    # Attaches files as ContractDocuments (triggers extraction pipeline)
  end
end
```

### AlertGeneratorService

Creates alerts from contract dates, personalized to each user's preferences.

```ruby
class AlertGeneratorService
  def initialize(contract)
  end

  def call
    # Clears regenerable (pending/snoozed) alerts
    # Generates expiry_warning, renewal_upcoming, notice_period_start alerts
    # Respects per-user AlertPreference (days_before_renewal, days_before_expiry)
    # Creates AlertRecipients for each org member
  end
end
```

### AlertDeliveryService

Delivers pending alerts via email (ActionMailer) or in-app.

```ruby
class AlertDeliveryService
  def initialize(alert)
  end

  def call
    # Skips if contract is expired/cancelled (auto-cancels alert)
    # Delivers to each unsent recipient (checks AlertPreference.email_enabled)
    # Marks alert as "sent", creates audit log entry
  end
end
```

---

## Background Jobs

```ruby
# Text extraction from uploaded documents
# Triggers AI extraction when all documents are done
class ExtractContractDocumentJob < ApplicationJob
  # Idempotent: skips if already completed
  # After extraction: checks if all docs done -> chains AiExtractContractJob
  # Checks extraction limit before chaining AI job
  # Broadcasts Turbo Stream updates for document status
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ContractTextExtractorService::UnsupportedFormatError
end

# AI extraction (separate from text extraction)
class AiExtractContractJob < ApplicationJob
  # Supports full and incremental modes (new_document_id kwarg)
  # Broadcasts Turbo Stream updates for AI status + key clauses
  # Handles draft contracts with additional form broadcasts
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ContractAiExtractorService::ExtractionError
  discard_on ContractAiExtractorService::ExtractionLimitReachedError
end

# Alert generation from contract dates
class GenerateContractAlertsJob < ApplicationJob
  def perform(contract_id)
    AlertGeneratorService.new(Contract.find(contract_id)).call
  end
end

# Daily delivery of pending alerts (runs at 7am)
class DailyAlertCheckJob < ApplicationJob
  def perform
    Alert.pending.due_on_or_before(Date.current).find_each do |alert|
      AlertDeliveryService.new(alert).call
    end
  end
end

# Status transitions: active -> expired/expiring_soon (runs at midnight)
class ContractStatusUpdaterJob < ApplicationJob
  def perform
    # Marks overdue contracts as expired, cancels their pending alerts
    # Marks contracts ending within 30 days as expiring_soon
  end
end

# Reset monthly AI extraction counters (runs 1st of each month)
class ResetMonthlyExtractionsJob < ApplicationJob
  def perform
    Organization.where("ai_extractions_count > 0").find_each(&:reset_monthly_extractions!)
  end
end

# Clean up stale draft contracts older than 7 days (runs at 3am)
class CleanStaleDraftsJob < ApplicationJob
  def perform
    Contract.draft.where(updated_at: ...7.days.ago).destroy_all
  end
end
```

### Recurring Schedule (config/recurring.yml)

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12

  daily_alert_check:
    class: DailyAlertCheckJob
    schedule: at 7am every day

  contract_status_updater:
    class: ContractStatusUpdaterJob
    schedule: at midnight every day

  reset_monthly_extractions:
    class: ResetMonthlyExtractionsJob
    schedule: on the 1st of every month at midnight

  clean_stale_drafts:
    class: CleanStaleDraftsJob
    schedule: at 3am every day
```

---

## Routes

```ruby
Rails.application.routes.draw do
  # Auth
  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # App
  resources :contracts do
    resources :documents, only: %i[create destroy], controller: "contract_documents"
    resource :extraction, only: %i[create], controller: "contract_extractions"
    collection do
      post :create_draft
      post :bulk_archive
      post :bulk_export
    end
  end

  resources :alerts, only: %i[index] do
    member do
      patch :acknowledge
      patch :snooze
    end
  end

  resource :alert_preference, only: %i[show update]
  resources :audit_logs, only: %i[index]

  # Billing
  resource :pricing, only: %i[show], controller: "pricing"
  resource :billing, only: %i[show], controller: "billing" do
    post :checkout
    get :portal
    get :success
  end
  mount Pay::Engine, at: "/pay"

  # Dashboard
  get "dashboard", to: "dashboard#show", as: :dashboard

  # Landing page
  root "pages#home"

  # Onboarding
  get  "onboarding/organization", to: "onboarding#organization"
  patch "onboarding/organization", to: "onboarding#update_organization"
  get  "onboarding/contract",     to: "onboarding#contract"
  post "onboarding/contract",     to: "onboarding#create_contract"
  post "onboarding/contract/skip", to: "onboarding#skip_contract"
  get  "onboarding/invite",       to: "onboarding#invite"
  post "onboarding/invite",       to: "onboarding#create_invite"
  post "onboarding/complete",     to: "onboarding#complete"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
```

---

## Controller Structure

```
app/controllers/
+-- application_controller.rb          # auth check, set_tenant (via Authentication concern)
+-- sessions_controller.rb             # login/logout
+-- registrations_controller.rb        # sign up (creates user + org), invitation acceptance
+-- passwords_controller.rb            # password reset
+-- dashboard_controller.rb            # main dashboard with summary widgets
+-- contracts_controller.rb            # CRUD + search/filter + bulk actions + draft creation
+-- contract_documents_controller.rb   # file upload/delete within contracts
+-- contract_extractions_controller.rb # trigger AI re-extraction
+-- alerts_controller.rb               # list alerts, acknowledge, snooze
+-- alert_preferences_controller.rb    # notification preferences per user
+-- audit_logs_controller.rb           # audit trail with filtering
+-- billing_controller.rb              # Stripe checkout, portal, subscription management
+-- pricing_controller.rb              # pricing page display
+-- onboarding_controller.rb           # multi-step onboarding wizard (org -> contract -> invite)
+-- pages_controller.rb                # marketing landing page
+-- concerns/
    +-- authentication.rb              # session-based auth, require_authentication
    +-- auditable.rb                   # automatic audit log creation
    +-- plan_enforcement.rb            # plan limit checks before actions
```

### Mailers

```
app/mailers/
+-- application_mailer.rb             # default from: notifications@huttalpact.com
+-- alert_mailer.rb                   # alert_notification (HTML + text)
+-- invitation_mailer.rb              # invite (token-based team invitation)
+-- passwords_mailer.rb               # password reset
```

---

## Phased Build Plan

### Phase 1: Foundation

#### Week 1: Auth + Multi-tenancy + Layout
- [x] Uncomment bcrypt, add gems, bundle install
- [x] Install Tailwind CSS
- [x] Run `bin/rails generate authentication`
- [x] Create Organization + Membership migrations
- [x] Set up acts_as_tenant
- [x] Build registration flow (creates user + org)
- [x] Build login/logout
- [x] Build app shell layout (sidebar, topbar, main content area)
- [x] Add HuttalPact branding to layout

#### Week 2: Contract CRUD
- [x] Create Contract migration
- [x] Build contracts#index with Turbo Frames
- [x] Build contracts#new / #create form
- [x] Build contracts#show detail page
- [x] Build contracts#edit / #update
- [x] Build contracts#destroy with confirmation
- [x] Add search and filter (by status, type, vendor, direction)
- [x] Add pagination with Pagy

#### Week 3: File Upload + Text Extraction
- [x] Create ContractDocument migration (with document_type, position columns)
- [x] Configure Active Storage for PDF/DOCX/TXT
- [x] Add server-side file validation (content type allowlist, 25 MB max size)
- [x] Build drag-and-drop file upload (Stimulus controller with client-side type/size checks)
- [x] Build ContractTextExtractorService (PDF + DOCX + TXT, with corrupt-file handling and text truncation)
- [x] Create ExtractContractDocumentJob (with idempotency guard, AI chaining logic, retry/discard policy)
- [x] Show extraction status with Turbo Streams (broadcast from job)
- [x] Display extracted text preview
- [x] Deletion guards during in-flight extraction
- [x] Test coverage for text extraction pipeline

### Phase 2: AI Intelligence

#### Week 4: AI Extraction
- [x] Integrate Anthropic Claude API
- [x] Build ContractAiExtractorService (full + incremental modes, reentrance guard)
- [x] Create KeyClause model + migration (with source_document_id FK)
- [x] Auto-populate contract fields from AI extraction (only fill blank fields in full mode)
- [x] AI output validation/coercion: sanitize enums, dates, numerics, booleans before persisting
- [x] Extraction limit enforcement in auto-extraction path and ContractAiExtractorService
- [x] Incremental extraction with user-edit preservation
- [x] Show extracted clauses on contract detail page
- [x] Build re-extract action for manual override (with extraction limit check)
- [x] Add confidence scores display (clamped 0-100)
- [x] Comprehensive test coverage for AI extraction

#### Week 5: Dashboard + Analytics
- [x] Build dashboard with contract summary widgets
- [x] Upcoming renewals list (next 30/60/90 days)
- [x] Expiring contracts list
- [x] Contract value by type/vendor chart
- [x] Status distribution overview
- [x] Quick-add contract shortcut

### Phase 3: Alerts + Polish

#### Week 6: Alert System
- [x] Create Alert + AlertRecipient migrations
- [x] Build AlertGeneratorService (creates alerts from contract dates)
- [x] Build AlertDeliveryService (sends emails via ActionMailer)
- [x] Set up DailyAlertCheckJob recurring schedule
- [x] Build ContractStatusUpdaterJob recurring schedule
- [x] Alert preferences per user
- [x] In-app notification dropdown

#### Week 7: Polish + UX
- [x] Audit log tracking (AuditLog model, Auditable concern, AuditLogsController)
- [x] Bulk actions (archive, export) with bulk_select_controller.js Stimulus
- [x] CSV export of contracts (full index + filtered + bulk selected)
- [x] Archived status (excluded from dashboard stats)
- [x] Empty states for all views
- [x] Error handling + flash messages
- [x] Loading states with Turbo
- [x] Mobile responsive adjustments

### Phase 4: Billing + Launch (partial)

#### Week 8: Billing
- [x] Integrate Pay gem + Stripe
- [x] Build pricing page
- [x] Build subscription management (checkout, portal, success flow)
- [x] Enforce plan limits (contract count, AI extractions, user count)
- [x] Build upgrade prompts
- [x] Plan sync from Stripe subscriptions (webhook-driven)
- [x] Monthly extraction counter reset job

#### Week 9: Pre-launch (partial)
- [x] Landing page (marketing layout with hero, features, testimonials, pricing teaser)
- [x] Onboarding wizard for new users (organization -> contract upload -> invite team)
- [x] Invitation system (token-based email invites, InvitationMailer)
- [x] Draft contract flow (upload-first, ContractDraftCreatorService, CleanStaleDraftsJob)
- [x] Alert email templates (alert_notification HTML + text)
- [x] Contract direction tracking (inbound/outbound = revenue/expense)
- [x] SEO basics (meta tags, structured data)
- [x] Security audit (Brakeman, bundler-audit)

#### Week 10: Launch
- [ ] Deploy to production with Kamal
- [ ] Configure S3 for Active Storage
- [ ] Set up Postmark for transactional email
- [ ] Set up error tracking (Sentry or similar)
- [ ] Set up analytics (Plausible or similar)
- [ ] Monitor and iterate

---

## Key Credentials Needed

| Credential | When needed | Purpose |
|---|---|---|
| Anthropic API key | Phase 2 (Week 4) | AI contract extraction |
| Stripe API keys | Phase 4 (Week 8) | Subscription billing |
| AWS S3 credentials | Phase 4 (Week 10) | Production file storage |
| Postmark API token | Phase 4 (Week 10) | Transactional email (production) |

---

## Target Customer Profile

**Primary**: Property management companies (5-50 properties)
- Pain: 20-100+ vendor contracts (HVAC, landscaping, pest control, insurance, leases)
- Cost of failure: $3K-$50K per missed auto-renewal
- Current tool: Spreadsheets, filing cabinets, email folders
- Budget: $49-$149/mo (trivial vs. one missed renewal)

**Secondary**: MSPs, consulting firms, multi-unit franchise operators, small manufacturers

**Go-to-market**: Industry-agnostic product, vertical marketing to property managers first.
