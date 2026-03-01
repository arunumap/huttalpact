class CreateRentEscalations < ActiveRecord::Migration[8.1]
  def change
    create_table :rent_escalations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.date :effective_date, null: false
      t.decimal :base_rent_monthly, precision: 12, scale: 2
      t.decimal :base_rent_annual, precision: 12, scale: 2
      t.string :escalation_type, null: false # fixed_percentage, cpi, fmv_reset, stepped, flat
      t.decimal :escalation_value, precision: 10, scale: 4 # %, dollar amount, or factor
      t.text :description
      t.integer :position, default: 0

      t.timestamps

      t.index [ :contract_id, :effective_date ]
    end
  end
end
