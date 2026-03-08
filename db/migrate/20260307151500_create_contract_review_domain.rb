class CreateContractReviewDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_reviews, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :ai_usage_log, null: true, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "open"
      t.string :review_trigger, null: false, default: "initial_extraction"
      t.integer :total_fields_count, null: false, default: 0
      t.integer :pending_fields_count, null: false, default: 0
      t.integer :looks_good_fields_count, null: false, default: 0
      t.integer :needs_review_fields_count, null: false, default: 0
      t.integer :blocked_fields_count, null: false, default: 0
      t.integer :open_conflicts_count, null: false, default: 0
      t.datetime :completed_at
      t.datetime :superseded_at

      t.timestamps
    end

    add_index :contract_reviews, [ :organization_id, :status, :created_at ], name: "index_contract_reviews_on_org_status_created"
    add_index :contract_reviews, :ai_usage_log_id, unique: true, where: "ai_usage_log_id IS NOT NULL", name: "index_contract_reviews_on_unique_ai_usage_log"
    add_index :contract_reviews, :contract_id, unique: true, where: "status = 'open'", name: "index_open_contract_reviews_on_contract_id"

    create_table :contract_review_fields, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract_review, null: false, foreign_key: true, type: :uuid
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :source_document, null: true, foreign_key: { to_table: :contract_documents }, type: :uuid
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :field_key, null: false
      t.string :field_family, null: false
      t.string :classification, null: false
      t.string :source_type, null: false
      t.string :readiness_bucket, null: false, default: "pending"
      t.string :review_status, null: false, default: "pending"
      t.boolean :repeatable, null: false, default: false
      t.integer :field_index
      t.boolean :gates_activation, null: false, default: false
      t.jsonb :extracted_value
      t.jsonb :approved_value
      t.jsonb :current_value
      t.text :derived_dependency_keys, array: true, null: false, default: []
      t.text :alert_family_keys, array: true, null: false, default: []
      t.string :source_document_name
      t.string :source_locator
      t.jsonb :source_span, null: false, default: {}
      t.text :review_note
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :contract_review_fields, [ :organization_id, :contract_review_id, :readiness_bucket ], name: "index_review_fields_on_org_review_readiness"
    add_index :contract_review_fields, [ :organization_id, :contract_review_id, :review_status ], name: "index_review_fields_on_org_review_status"
    add_index :contract_review_fields, [ :contract_id, :field_key ], name: "index_review_fields_on_contract_and_key"
    add_index :contract_review_fields, [ :contract_review_id, :gates_activation ], name: "index_review_fields_on_review_and_gate"
    add_index :contract_review_fields, [ :contract_review_id, :field_key ], unique: true, where: "field_index IS NULL", name: "index_review_fields_on_review_and_key"
    add_index :contract_review_fields, [ :contract_review_id, :field_key, :field_index ], unique: true, where: "field_index IS NOT NULL", name: "index_review_fields_on_review_key_index"

    create_table :contract_review_conflicts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract_review, null: false, foreign_key: true, type: :uuid
      t.references :contract_review_field, null: false, foreign_key: true, type: :uuid
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :resolved_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :conflict_type, null: false
      t.string :status, null: false, default: "open"
      t.boolean :blocks_activation, null: false, default: true
      t.string :summary, null: false
      t.text :details
      t.jsonb :extracted_value
      t.jsonb :approved_value
      t.jsonb :resolution_value
      t.text :alert_family_keys, array: true, null: false, default: []
      t.jsonb :source_span, null: false, default: {}
      t.datetime :resolved_at
      t.text :resolution_notes

      t.timestamps
    end

    add_index :contract_review_conflicts, [ :organization_id, :status, :created_at ], name: "index_review_conflicts_on_org_status_created"
    add_index :contract_review_conflicts, [ :contract_review_id, :status ], name: "index_review_conflicts_on_review_and_status"
    add_index :contract_review_conflicts, [ :contract_review_field_id, :status ], name: "index_review_conflicts_on_field_and_status"

    create_table :contract_review_field_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract_review, null: false, foreign_key: true, type: :uuid
      t.references :contract_review_field, null: false, foreign_key: true, type: :uuid
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.string :action, null: false
      t.string :from_review_status
      t.string :to_review_status
      t.jsonb :from_value
      t.jsonb :to_value
      t.jsonb :metadata, null: false, default: {}
      t.text :note

      t.timestamps
    end

    add_index :contract_review_field_events, [ :contract_review_field_id, :created_at ], name: "index_review_field_events_on_field_created"
    add_index :contract_review_field_events, [ :organization_id, :created_at ], name: "index_review_field_events_on_org_created"
    add_index :contract_review_field_events, [ :contract_review_id, :action ], name: "index_review_field_events_on_review_action"
  end
end
