class CreateBulkDeleteOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :bulk_delete_operations, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "queued"
      t.integer :requested_count, null: false, default: 0
      t.integer :processed_count, null: false, default: 0
      t.integer :deleted_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.text :error_message
      t.datetime :completed_at

      t.timestamps
    end

    add_index :bulk_delete_operations, [ :organization_id, :user_id, :created_at ], name: "index_bulk_delete_ops_on_org_user_created_at"
    add_index :bulk_delete_operations, [ :organization_id, :status, :created_at ], name: "index_bulk_delete_ops_on_org_status_created_at"
  end
end
