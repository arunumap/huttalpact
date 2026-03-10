class AddOrphanedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :orphaned_at, :datetime
  end
end
