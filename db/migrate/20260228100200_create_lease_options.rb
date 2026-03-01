class CreateLeaseOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :lease_options, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.string :option_type, null: false # renewal, expansion, termination, purchase, rofr, rofo
      t.date :exercise_deadline
      t.date :notice_deadline
      t.integer :term_length_months
      t.text :rent_terms
      t.decimal :penalty_amount, precision: 12, scale: 2
      t.text :conditions
      t.integer :position, default: 0

      t.timestamps

      t.index [ :contract_id, :option_type ]
      t.index :notice_deadline
    end
  end
end
