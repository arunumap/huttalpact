class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime
    execute <<~SQL.squish
      UPDATE users
      SET email_verified_at = CURRENT_TIMESTAMP
      WHERE email_verified_at IS NULL
    SQL
  end

  def down
    remove_column :users, :email_verified_at
  end
end
