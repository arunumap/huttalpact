class CreatePlanTiers < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_tiers, id: :uuid do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.integer :rank, null: false
      t.integer :position, null: false, default: 0

      t.integer :contract_limit
      t.integer :extraction_limit
      t.integer :user_limit
      t.integer :audit_log_days

      t.integer :monthly_price_cents, null: false, default: 0
      t.integer :annual_price_cents, null: false, default: 0
      t.string :monthly_lookup_key
      t.string :annual_lookup_key

      t.string :stripe_product_id
      t.string :stripe_monthly_price_id
      t.string :stripe_annual_price_id

      t.boolean :active, null: false, default: true
      t.boolean :visible_on_pricing_page, null: false, default: true
      t.boolean :featured, null: false, default: false
      t.boolean :system_tier, null: false, default: false
      t.boolean :default_tier, null: false, default: false

      t.text :feature_list, array: true, null: false, default: []

      t.timestamps
    end

    add_index :plan_tiers, :slug, unique: true
    add_index :plan_tiers, :rank, unique: true
    add_index :plan_tiers, :position
    add_index :plan_tiers, :active
    add_index :plan_tiers, :visible_on_pricing_page
    add_index :plan_tiers, :default_tier
  end
end
