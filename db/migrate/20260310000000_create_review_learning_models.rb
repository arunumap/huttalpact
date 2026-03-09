class CreateReviewLearningModels < ActiveRecord::Migration[8.1]
  def change
    create_table :review_learning_events, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :contract, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :contract_review, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :contract_review_field, type: :uuid, null: false,
                                          foreign_key: { on_delete: :cascade },
                                          index: { unique: true }
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :source_document, type: :uuid, foreign_key: { to_table: :contract_documents, on_delete: :nullify }
      t.references :ai_usage_log, type: :uuid, foreign_key: { on_delete: :nullify }

      t.string :review_type, null: false
      t.string :contract_type, null: false, default: "unknown"
      t.string :field_name, null: false
      t.string :field_group, null: false
      t.string :decision, null: false
      t.integer :confidence
      t.integer :confidence_threshold, null: false
      t.boolean :needs_review, null: false, default: true
      t.boolean :corrected, null: false, default: false
      t.text :extracted_value
      t.text :final_value
      t.text :user_value
      t.text :source_excerpt
      t.string :source_match_strategy
      t.boolean :source_excerpt_present, null: false, default: false
      t.jsonb :source_locator, null: false, default: {}
      t.string :evidence_quality, null: false, default: "missing"
      t.integer :evidence_quality_score
      t.jsonb :field_metadata, null: false, default: {}
      t.jsonb :review_metadata, null: false, default: {}
      t.datetime :reviewed_at, null: false

      t.timestamps
    end

    add_index :review_learning_events, [ :organization_id, :reviewed_at ], name: "idx_review_learning_events_on_org_reviewed_at"
    add_index :review_learning_events, [ :organization_id, :contract_type, :field_name ],
              name: "idx_review_learning_events_on_org_type_field"
    add_index :review_learning_events, [ :organization_id, :decision, :reviewed_at ],
              name: "idx_review_learning_events_on_org_decision_reviewed_at"
    add_index :review_learning_events, [ :organization_id, :field_group, :reviewed_at ],
              name: "idx_review_learning_events_on_org_group_reviewed_at"
    add_index :review_learning_events, [ :organization_id, :confidence, :corrected ],
              name: "idx_review_learning_events_on_org_confidence_corrected"
    add_index :review_learning_events, :field_metadata, using: :gin
    add_index :review_learning_events, :review_metadata, using: :gin
    add_index :review_learning_events, :source_locator, using: :gin

    create_table :review_learning_aggregates, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :aggregate_type, null: false
      t.date :period_start_date, null: false
      t.date :period_end_date, null: false
      t.string :dimension_key, null: false
      t.integer :sample_size, null: false, default: 0
      t.integer :source_version, null: false, default: 1
      t.datetime :last_event_at
      t.jsonb :dimensions, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}

      t.timestamps
    end

    add_index :review_learning_aggregates,
              [ :organization_id, :aggregate_type, :period_start_date, :period_end_date, :dimension_key ],
              unique: true, name: "idx_review_learning_aggregates_uniqueness"
    add_index :review_learning_aggregates, [ :organization_id, :aggregate_type, :period_start_date ],
              name: "idx_review_learning_aggregates_on_org_type_start"
    add_index :review_learning_aggregates, :dimensions, using: :gin
    add_index :review_learning_aggregates, :metrics, using: :gin
  end
end
