class CreateAdminSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_sessions, id: :uuid do |t|
      t.references :admin_user, null: false, foreign_key: true, type: :uuid
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
  end
end
