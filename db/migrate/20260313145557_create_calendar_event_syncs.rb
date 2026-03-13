class CreateCalendarEventSyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_event_syncs, id: :uuid do |t|
      t.references :calendar_connection, null: false, type: :uuid, foreign_key: true
      t.references :organization, null: false, type: :uuid, foreign_key: true
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.string :event_category, null: false
      t.string :remote_event_id
      t.string :remote_calendar_id, null: false
      t.string :payload_fingerprint
      t.string :sync_status, null: false, default: "pending"
      t.datetime :last_synced_at
      t.text :last_error
      t.integer :retry_count, null: false, default: 0
      t.timestamps
    end

    add_index :calendar_event_syncs,
              [:calendar_connection_id, :source_type, :source_id, :event_category],
              unique: true, name: "idx_cal_event_syncs_connection_source"
    add_index :calendar_event_syncs, [:source_type, :source_id]
    add_index :calendar_event_syncs, [:sync_status]
    add_index :calendar_event_syncs, [:organization_id, :sync_status]
  end
end
