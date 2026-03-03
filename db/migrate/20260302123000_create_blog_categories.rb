class CreateBlogCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :blog_categories, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :blog_categories, :slug, unique: true
    add_index :blog_categories, :position
  end
end
