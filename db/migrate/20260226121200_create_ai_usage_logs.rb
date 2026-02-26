class CreateAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_usage_logs, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :contract, null: true, foreign_key: true, type: :uuid
      t.string :model_name, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0
      t.string :extraction_mode, null: false, default: "full"
      t.boolean :success, null: false, default: true
      t.text :error_message
      t.integer :duration_ms

      t.datetime :created_at, null: false
    end

    add_index :ai_usage_logs, :created_at
    add_index :ai_usage_logs, [ :success, :created_at ]
  end
end
