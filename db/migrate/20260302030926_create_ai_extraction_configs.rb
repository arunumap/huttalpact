class CreateAiExtractionConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_extraction_configs, id: :uuid do |t|
      t.string :extraction_type, null: false
      t.string :ai_model, null: false
      t.integer :max_tokens, null: false
      t.decimal :temperature, precision: 3, scale: 2
      t.decimal :top_p, precision: 3, scale: 2
      t.integer :top_k
      t.decimal :input_cost_per_million, precision: 10, scale: 4, null: false
      t.decimal :output_cost_per_million, precision: 10, scale: 4, null: false
      t.boolean :active, default: false, null: false
      t.integer :version, null: false
      t.text :notes
      t.references :created_by, type: :uuid, foreign_key: { to_table: :admin_users }

      t.timestamps
    end

    add_index :ai_extraction_configs, %i[extraction_type version], unique: true
    add_index :ai_extraction_configs, %i[extraction_type active]

    # Seed initial configs from current hardcoded values
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO ai_extraction_configs (id, extraction_type, ai_model, max_tokens, input_cost_per_million, output_cost_per_million, active, version, notes, created_at, updated_at)
          VALUES
            (gen_random_uuid(), 'generic_full', 'claude-sonnet-4-20250514', 4096, 3.0, 15.0, true, 1, 'Initial config seeded from hardcoded values', NOW(), NOW()),
            (gen_random_uuid(), 'generic_incremental', 'claude-sonnet-4-20250514', 4096, 3.0, 15.0, true, 1, 'Initial config seeded from hardcoded values', NOW(), NOW()),
            (gen_random_uuid(), 'lease_full', 'claude-sonnet-4-20250514', 8192, 3.0, 15.0, true, 1, 'Initial config seeded from hardcoded values', NOW(), NOW()),
            (gen_random_uuid(), 'lease_incremental', 'claude-sonnet-4-20250514', 8192, 3.0, 15.0, true, 1, 'Initial config seeded from hardcoded values', NOW(), NOW())
        SQL
      end
    end
  end
end
