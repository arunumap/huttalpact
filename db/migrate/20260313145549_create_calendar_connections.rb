class CreateCalendarConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_connections, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :organization, null: false, type: :uuid, foreign_key: true
      t.string :provider, null: false
      t.text :access_token, null: false
      t.text :refresh_token
      t.datetime :token_expires_at
      t.string :provider_uid
      t.string :provider_email
      t.string :status, null: false, default: "active"
      t.text :last_error
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :calendar_connections, [ :user_id, :organization_id, :provider ],
              unique: true, name: "idx_calendar_connections_user_org_provider"
    add_index :calendar_connections, [ :organization_id, :status ]
  end
end
