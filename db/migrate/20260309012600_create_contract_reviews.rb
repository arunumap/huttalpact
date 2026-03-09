class CreateContractReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_reviews, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :review_type, null: false
      t.integer :confidence_threshold, null: false, default: 80
      t.text :ai_extraction_snapshot
      t.integer :total_fields, null: false, default: 0
      t.integer :reviewed_fields, null: false, default: 0
      t.datetime :completed_at
      t.references :completed_by, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :contract_reviews, [ :contract_id, :status ]

    create_table :contract_review_fields, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract_review, type: :uuid, null: false, foreign_key: true
      t.string :field_name, null: false
      t.string :field_group, null: false
      t.string :display_name, null: false
      t.text :extracted_value
      t.integer :confidence
      t.text :source_excerpt
      t.references :source_document, type: :uuid, foreign_key: { to_table: :contract_documents }, null: true
      t.jsonb :source_locator
      t.string :source_match_strategy
      t.text :reasoning
      t.boolean :needs_review, null: false, default: true
      t.string :status, null: false, default: "pending"
      t.text :user_value
      t.datetime :reviewed_at
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }, null: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :contract_review_fields, [ :contract_review_id, :status ]
    add_index :contract_review_fields, [ :contract_review_id, :field_name ], unique: true
    add_index :contract_review_fields, :source_locator, using: :gin
  end
end
