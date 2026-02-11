class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, foreign_key: true
      t.references :contract, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.text :details
      t.timestamps
    end

    add_index :audit_logs, [ :organization_id, :created_at ]
    add_index :audit_logs, :action
  end
end
