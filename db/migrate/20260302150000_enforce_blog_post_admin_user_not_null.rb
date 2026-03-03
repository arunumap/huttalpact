class EnforceBlogPostAdminUserNotNull < ActiveRecord::Migration[8.1]
  def up
    null_count = execute("SELECT COUNT(*) FROM blog_posts WHERE admin_user_id IS NULL").first["count"].to_i
    if null_count.positive?
      raise ActiveRecord::IrreversibleMigration, "Cannot enforce NOT NULL: blog_posts with null admin_user_id exist"
    end

    change_column_null :blog_posts, :admin_user_id, false
  end

  def down
    change_column_null :blog_posts, :admin_user_id, true
  end
end
