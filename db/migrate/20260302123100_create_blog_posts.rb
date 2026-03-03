class CreateBlogPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :blog_posts, id: :uuid do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :body, null: false
      t.text :excerpt
      t.string :meta_description
      t.string :canonical_url
      t.string :og_image_url
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.references :admin_user, type: :uuid, foreign_key: true
      t.references :blog_category, type: :uuid, foreign_key: true

      t.timestamps
    end

    add_index :blog_posts, :slug, unique: true
    add_index :blog_posts, :status
    add_index :blog_posts, :published_at
  end
end
