# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_04_170000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "admin_user_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["admin_user_id"], name: "index_admin_sessions_on_admin_user_id"
  end

  create_table "admin_users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_admin_users_on_email_address", unique: true
  end

  create_table "ai_extraction_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.string "ai_model", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "extraction_type", null: false
    t.decimal "input_cost_per_million", precision: 10, scale: 4, null: false
    t.integer "max_tokens", null: false
    t.text "notes"
    t.decimal "output_cost_per_million", precision: 10, scale: 4, null: false
    t.integer "request_timeout"
    t.decimal "temperature", precision: 3, scale: 2
    t.integer "top_k"
    t.decimal "top_p", precision: 3, scale: 2
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["created_by_id"], name: "index_ai_extraction_configs_on_created_by_id"
    t.index ["extraction_type", "active"], name: "index_ai_extraction_configs_on_extraction_type_and_active"
    t.index ["extraction_type", "version"], name: "index_ai_extraction_configs_on_extraction_type_and_version", unique: true
  end

  create_table "ai_usage_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_extraction_config_id"
    t.string "ai_model", null: false
    t.uuid "contract_id"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.string "extraction_mode", default: "full", null: false
    t.integer "input_tokens", default: 0, null: false
    t.uuid "organization_id", null: false
    t.integer "output_tokens", default: 0, null: false
    t.boolean "success", default: true, null: false
    t.integer "total_tokens", default: 0, null: false
    t.index ["ai_extraction_config_id"], name: "index_ai_usage_logs_on_ai_extraction_config_id"
    t.index ["contract_id"], name: "index_ai_usage_logs_on_contract_id"
    t.index ["created_at"], name: "index_ai_usage_logs_on_created_at"
    t.index ["organization_id"], name: "index_ai_usage_logs_on_organization_id"
    t.index ["success", "created_at"], name: "index_ai_usage_logs_on_success_and_created_at"
  end

  create_table "alert_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "days_before_cam_reconciliation", default: 30
    t.integer "days_before_expiry", default: 14, null: false
    t.integer "days_before_milestone", default: 14
    t.integer "days_before_option_exercise", default: 90
    t.integer "days_before_renewal", default: 30, null: false
    t.integer "days_before_rent_escalation", default: 30
    t.boolean "email_enabled", default: true, null: false
    t.boolean "in_app_enabled", default: true, null: false
    t.uuid "organization_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["organization_id"], name: "index_alert_preferences_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_alert_preferences_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_alert_preferences_on_user_id"
  end

  create_table "alert_recipients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "alert_id", null: false
    t.string "channel", default: "email", null: false
    t.datetime "created_at", null: false
    t.datetime "read_at"
    t.datetime "sent_at"
    t.date "snoozed_until"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["alert_id", "user_id"], name: "index_alert_recipients_on_alert_id_and_user_id", unique: true
    t.index ["alert_id"], name: "index_alert_recipients_on_alert_id"
    t.index ["user_id", "read_at"], name: "index_alert_recipients_on_user_unread"
    t.index ["user_id"], name: "index_alert_recipients_on_user_id"
  end

  create_table "alerts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "alert_type", null: false
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.text "message"
    t.uuid "organization_id", null: false
    t.string "status", default: "pending", null: false
    t.date "trigger_date", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id", "alert_type"], name: "index_alerts_on_contract_id_and_alert_type"
    t.index ["contract_id"], name: "index_alerts_on_contract_id"
    t.index ["organization_id", "status", "trigger_date"], name: "index_alerts_on_org_status_trigger"
    t.index ["organization_id"], name: "index_alerts_on_organization_id"
    t.index ["status"], name: "index_alerts_on_status"
    t.index ["trigger_date"], name: "index_alerts_on_trigger_date"
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "contract_id"
    t.datetime "created_at", null: false
    t.text "details"
    t.uuid "organization_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["contract_id"], name: "index_audit_logs_on_contract_id"
    t.index ["organization_id", "created_at"], name: "index_audit_logs_on_organization_id_and_created_at"
    t.index ["organization_id"], name: "index_audit_logs_on_organization_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "blog_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_blog_categories_on_position"
    t.index ["slug"], name: "index_blog_categories_on_slug", unique: true
  end

  create_table "blog_posts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "admin_user_id", null: false
    t.uuid "blog_category_id"
    t.text "body", null: false
    t.string "canonical_url"
    t.datetime "created_at", null: false
    t.text "excerpt"
    t.string "meta_description"
    t.string "og_image_url"
    t.datetime "published_at"
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_blog_posts_on_admin_user_id"
    t.index ["blog_category_id"], name: "index_blog_posts_on_blog_category_id"
    t.index ["published_at"], name: "index_blog_posts_on_published_at"
    t.index ["slug"], name: "index_blog_posts_on_slug", unique: true
    t.index ["status"], name: "index_blog_posts_on_status"
  end

  create_table "contract_documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.string "document_type", default: "main_contract", null: false
    t.text "extracted_text"
    t.string "extraction_status", default: "pending", null: false
    t.integer "page_count"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id", "created_at"], name: "index_contract_documents_on_contract_id_and_created_at"
    t.index ["contract_id", "position"], name: "index_contract_documents_on_contract_id_and_position"
    t.index ["contract_id"], name: "index_contract_documents_on_contract_id"
  end

  create_table "contracts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "ai_extracted_data"
    t.text "ai_summary"
    t.boolean "auto_renews", default: false
    t.string "contract_type"
    t.datetime "created_at", null: false
    t.string "direction", default: "outbound", null: false
    t.date "end_date"
    t.string "extraction_status", default: "pending", null: false
    t.text "last_changes_summary"
    t.decimal "monthly_value", precision: 10, scale: 2
    t.date "next_renewal_date"
    t.text "notes"
    t.integer "notice_period_days"
    t.uuid "organization_id", null: false
    t.string "premises_address"
    t.string "renewal_term"
    t.date "start_date"
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.decimal "total_value", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id"
    t.string "vendor_name"
    t.index ["contract_type"], name: "index_contracts_on_contract_type"
    t.index ["direction"], name: "index_contracts_on_direction"
    t.index ["end_date"], name: "index_contracts_on_end_date"
    t.index ["next_renewal_date"], name: "index_contracts_on_next_renewal_date"
    t.index ["organization_id"], name: "index_contracts_on_organization_id"
    t.index ["premises_address"], name: "index_contracts_on_premises_address"
    t.index ["status"], name: "index_contracts_on_status"
    t.index ["uploaded_by_id"], name: "index_contracts_on_uploaded_by_id"
  end

  create_table "extraction_feedbacks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_usage_log_id"
    t.text "comment"
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.uuid "organization_id", null: false
    t.string "rating", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["ai_usage_log_id"], name: "index_extraction_feedbacks_on_ai_usage_log_id"
    t.index ["contract_id", "user_id"], name: "index_extraction_feedbacks_on_contract_id_and_user_id", unique: true
    t.index ["contract_id"], name: "index_extraction_feedbacks_on_contract_id"
    t.index ["organization_id"], name: "index_extraction_feedbacks_on_organization_id"
    t.index ["user_id"], name: "index_extraction_feedbacks_on_user_id"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at"
    t.uuid "inviter_id", null: false
    t.uuid "organization_id", null: false
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["organization_id", "accepted_at"], name: "index_invitations_on_organization_id_and_accepted_at"
    t.index ["organization_id", "email"], name: "index_invitations_on_organization_id_and_email"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "key_clauses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "clause_type", null: false
    t.integer "confidence_score"
    t.text "content"
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.string "page_reference"
    t.uuid "source_document_id"
    t.datetime "updated_at", null: false
    t.index ["contract_id", "clause_type"], name: "index_key_clauses_on_contract_id_and_clause_type"
    t.index ["contract_id"], name: "index_key_clauses_on_contract_id"
    t.index ["source_document_id"], name: "index_key_clauses_on_source_document_id"
  end

  create_table "lease_details", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "cam_audit_rights", default: false
    t.decimal "cam_base_amount", precision: 12, scale: 2
    t.integer "cam_base_year"
    t.decimal "cam_cap_percentage", precision: 5, scale: 2
    t.string "cam_cap_type"
    t.decimal "cam_controllable_cap", precision: 5, scale: 2
    t.boolean "cam_gross_up_provision", default: false
    t.integer "cam_reconciliation_month"
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.integer "free_rent_months"
    t.string "lease_type"
    t.decimal "load_factor", precision: 5, scale: 4
    t.decimal "parking_monthly_cost", precision: 10, scale: 2
    t.integer "parking_spaces"
    t.decimal "percentage_rent_breakpoint", precision: 12, scale: 2
    t.decimal "percentage_rent_rate", precision: 5, scale: 2
    t.date "percentage_rent_report_date"
    t.string "permitted_use"
    t.date "rent_commencement_date"
    t.decimal "rentable_sqft", precision: 10, scale: 2
    t.decimal "security_deposit", precision: 12, scale: 2
    t.text "security_deposit_conditions"
    t.decimal "ti_allowance_psf", precision: 10, scale: 2
    t.decimal "ti_amortization_rate", precision: 5, scale: 2
    t.integer "ti_amortization_term_months"
    t.date "ti_deadline"
    t.string "ti_disbursement_type"
    t.text "ti_landlord_work_description"
    t.text "ti_tenant_work_description"
    t.decimal "ti_total_amount", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "usable_sqft", precision: 10, scale: 2
    t.index ["contract_id"], name: "index_lease_details_on_contract_id", unique: true
  end

  create_table "lease_milestones", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date", null: false
    t.string "milestone_type", null: false
    t.uuid "organization_id", null: false
    t.string "recurrence_interval"
    t.boolean "recurring", default: false
    t.datetime "updated_at", null: false
    t.index ["contract_id", "milestone_type"], name: "index_lease_milestones_on_contract_id_and_milestone_type"
    t.index ["contract_id"], name: "index_lease_milestones_on_contract_id"
    t.index ["organization_id", "due_date"], name: "index_lease_milestones_on_organization_id_and_due_date"
    t.index ["organization_id"], name: "index_lease_milestones_on_organization_id"
  end

  create_table "lease_options", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "conditions"
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.date "exercise_deadline"
    t.date "notice_deadline"
    t.string "option_type", null: false
    t.decimal "penalty_amount", precision: 12, scale: 2
    t.integer "position", default: 0
    t.text "rent_terms"
    t.integer "term_length_months"
    t.datetime "updated_at", null: false
    t.index ["contract_id", "option_type"], name: "index_lease_options_on_contract_id_and_option_type"
    t.index ["contract_id"], name: "index_lease_options_on_contract_id"
    t.index ["notice_deadline"], name: "index_lease_options_on_notice_deadline"
  end

  create_table "memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "organization_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_memberships_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "ai_extractions_count", default: 0, null: false
    t.datetime "ai_extractions_reset_at"
    t.integer "contracts_count", default: 0
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "onboarding_completed_at"
    t.integer "onboarding_step", default: 0, null: false
    t.string "pending_downgrade_schedule_id"
    t.string "pending_plan"
    t.datetime "pending_plan_effective_at"
    t.string "pending_plan_interval"
    t.string "plan", default: "free", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["pending_plan_effective_at"], name: "index_organizations_on_pending_plan_effective_at"
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "pay_charges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.integer "application_fee_amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.uuid "customer_id", null: false
    t.jsonb "data"
    t.jsonb "metadata"
    t.jsonb "object"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.uuid "subscription_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.boolean "default"
    t.datetime "deleted_at", precision: nil
    t.jsonb "object"
    t.uuid "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.boolean "default"
    t.uuid "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "customer_id", null: false
    t.jsonb "data"
    t.boolean "default"
    t.string "payment_method_type"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "current_period_end", precision: nil
    t.datetime "current_period_start", precision: nil
    t.uuid "customer_id", null: false
    t.jsonb "data"
    t.datetime "ends_at", precision: nil
    t.jsonb "metadata"
    t.boolean "metered"
    t.string "name", null: false
    t.jsonb "object"
    t.string "pause_behavior"
    t.datetime "pause_resumes_at", precision: nil
    t.datetime "pause_starts_at", precision: nil
    t.string "payment_method_id"
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.string "stripe_account"
    t.datetime "trial_ends_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "event"
    t.string "event_type"
    t.string "processor"
    t.datetime "updated_at", null: false
  end

  create_table "plan_tiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "annual_lookup_key"
    t.integer "annual_price_cents", default: 0, null: false
    t.integer "audit_log_days"
    t.integer "contract_limit"
    t.datetime "created_at", null: false
    t.boolean "default_tier", default: false, null: false
    t.text "description"
    t.integer "extraction_limit"
    t.text "feature_list", default: [], null: false, array: true
    t.boolean "featured", default: false, null: false
    t.string "monthly_lookup_key"
    t.integer "monthly_price_cents", default: 0, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "rank", null: false
    t.string "slug", null: false
    t.string "stripe_annual_price_id"
    t.string "stripe_monthly_price_id"
    t.string "stripe_product_id"
    t.boolean "system_tier", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_limit"
    t.boolean "visible_on_pricing_page", default: true, null: false
    t.index ["active"], name: "index_plan_tiers_on_active"
    t.index ["default_tier"], name: "index_plan_tiers_on_default_tier"
    t.index ["position"], name: "index_plan_tiers_on_position"
    t.index ["rank"], name: "index_plan_tiers_on_rank", unique: true
    t.index ["slug"], name: "index_plan_tiers_on_slug", unique: true
    t.index ["visible_on_pricing_page"], name: "index_plan_tiers_on_visible_on_pricing_page"
  end

  create_table "rent_escalations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "base_rent_annual", precision: 12, scale: 2
    t.decimal "base_rent_monthly", precision: 12, scale: 2
    t.uuid "contract_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "effective_date", null: false
    t.string "escalation_type", null: false
    t.decimal "escalation_value", precision: 10, scale: 4
    t.integer "position", default: 0
    t.datetime "updated_at", null: false
    t.index ["contract_id", "effective_date"], name: "index_rent_escalations_on_contract_id_and_effective_date"
    t.index ["contract_id"], name: "index_rent_escalations_on_contract_id"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "password_digest", null: false
    t.datetime "terms_accepted_at"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_sessions", "admin_users"
  add_foreign_key "ai_extraction_configs", "admin_users", column: "created_by_id"
  add_foreign_key "ai_usage_logs", "ai_extraction_configs"
  add_foreign_key "ai_usage_logs", "contracts"
  add_foreign_key "ai_usage_logs", "organizations"
  add_foreign_key "alert_preferences", "organizations"
  add_foreign_key "alert_preferences", "users"
  add_foreign_key "alert_recipients", "alerts", on_delete: :cascade
  add_foreign_key "alert_recipients", "users"
  add_foreign_key "alerts", "contracts", on_delete: :cascade
  add_foreign_key "alerts", "organizations"
  add_foreign_key "audit_logs", "contracts", on_delete: :nullify
  add_foreign_key "audit_logs", "organizations"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "blog_posts", "admin_users"
  add_foreign_key "blog_posts", "blog_categories"
  add_foreign_key "contract_documents", "contracts", on_delete: :cascade
  add_foreign_key "contracts", "organizations"
  add_foreign_key "contracts", "users", column: "uploaded_by_id"
  add_foreign_key "extraction_feedbacks", "ai_usage_logs"
  add_foreign_key "extraction_feedbacks", "contracts"
  add_foreign_key "extraction_feedbacks", "organizations"
  add_foreign_key "extraction_feedbacks", "users"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "key_clauses", "contract_documents", column: "source_document_id", on_delete: :cascade
  add_foreign_key "key_clauses", "contracts", on_delete: :cascade
  add_foreign_key "lease_details", "contracts", on_delete: :cascade
  add_foreign_key "lease_milestones", "contracts", on_delete: :cascade
  add_foreign_key "lease_milestones", "organizations"
  add_foreign_key "lease_options", "contracts", on_delete: :cascade
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "rent_escalations", "contracts", on_delete: :cascade
  add_foreign_key "sessions", "users"
end
