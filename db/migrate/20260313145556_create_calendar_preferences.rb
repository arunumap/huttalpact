class CreateCalendarPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_preferences, id: :uuid do |t|
      t.references :calendar_connection, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :organization, null: false, type: :uuid, foreign_key: true
      t.string :remote_calendar_id, null: false
      t.string :remote_calendar_name
      t.boolean :sync_enabled, null: false, default: true
      t.jsonb :enabled_categories, null: false, default: []
      t.timestamps
    end

    add_index :calendar_preferences, [:calendar_connection_id],
              unique: true, name: "idx_calendar_prefs_connection"
    add_index :calendar_preferences, [:user_id, :organization_id]
  end
end
