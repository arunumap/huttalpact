class CreateAlertPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_preferences, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.boolean :email_enabled, default: true, null: false
      t.boolean :in_app_enabled, default: true, null: false
      t.integer :days_before_renewal, default: 30, null: false
      t.integer :days_before_expiry, default: 14, null: false
      t.timestamps
    end

    add_index :alert_preferences, [ :user_id, :organization_id ], unique: true
  end
end
