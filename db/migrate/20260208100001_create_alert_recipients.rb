class CreateAlertRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_recipients, id: :uuid do |t|
      t.references :alert, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :channel, default: "email", null: false
      t.datetime :sent_at
      t.datetime :read_at
      t.timestamps
    end

    add_index :alert_recipients, [ :alert_id, :user_id ], unique: true
    add_index :alert_recipients, [ :user_id, :read_at ],
              name: "index_alert_recipients_on_user_unread"
  end
end
