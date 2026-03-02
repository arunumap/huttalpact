class CreateExtractionFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :extraction_feedbacks, id: :uuid do |t|
      t.references :contract, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :ai_usage_log, type: :uuid, foreign_key: true
      t.string :rating, null: false
      t.text :comment

      t.timestamps
    end

    add_index :extraction_feedbacks, %i[contract_id user_id], unique: true
  end
end
