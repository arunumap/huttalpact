class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :contract, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :alert_type, null: false
      t.date :trigger_date, null: false
      t.string :status, default: "pending", null: false
      t.text :message
      t.timestamps
    end

    add_index :alerts, :trigger_date
    add_index :alerts, :status
    add_index :alerts, [ :contract_id, :alert_type ]
    add_index :alerts, [ :organization_id, :status, :trigger_date ],
              name: "index_alerts_on_org_status_trigger"
  end
end
