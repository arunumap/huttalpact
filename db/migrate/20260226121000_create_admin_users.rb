class CreateAdminUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_users, id: :uuid do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :first_name
      t.string :last_name

      t.timestamps
    end

    add_index :admin_users, :email_address, unique: true
  end
end
