class AddExtractionOverageBilling < ActiveRecord::Migration[8.1]
  def change
    add_column :plan_tiers, :extraction_overage_cents, :integer, null: false, default: 0
    add_column :organizations, :ai_extractions_overage_count, :integer, null: false, default: 0

    create_table :extraction_overage_charges, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :contract, type: :uuid, foreign_key: { on_delete: :nullify }
      t.datetime :extraction_period_start_at, null: false
      t.integer :usage_position, null: false
      t.integer :overage_cents, null: false
      t.string :status, null: false, default: "pending"
      t.string :stripe_invoice_item_id
      t.string :idempotency_key, null: false
      t.text :error_message
      t.datetime :billed_at
      t.timestamps
    end

    add_index :extraction_overage_charges,
      [ :organization_id, :extraction_period_start_at, :usage_position ],
      unique: true,
      name: "index_extraction_overage_charges_on_org_period_position"
    add_index :extraction_overage_charges, [ :status, :created_at ]
    add_index :extraction_overage_charges, :idempotency_key, unique: true
  end
end
