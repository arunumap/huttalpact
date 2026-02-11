class CreateContracts < ActiveRecord::Migration[8.1]
  def change
    create_table :contracts, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.string :vendor_name
      t.string :status, default: "active", null: false
      t.string :contract_type
      t.date :start_date
      t.date :end_date
      t.date :next_renewal_date
      t.integer :notice_period_days
      t.decimal :monthly_value, precision: 10, scale: 2
      t.decimal :total_value, precision: 12, scale: 2
      t.boolean :auto_renews, default: false
      t.string :renewal_term
      t.text :notes
      t.text :ai_extracted_data
      t.string :extraction_status, default: "pending", null: false
      t.references :uploaded_by, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :contracts, :status
    add_index :contracts, :contract_type
    add_index :contracts, :end_date
    add_index :contracts, :next_renewal_date
  end
end
