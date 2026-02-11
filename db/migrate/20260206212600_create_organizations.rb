class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :plan, default: "free", null: false
      t.integer :contracts_count, default: 0

      t.timestamps
    end
    add_index :organizations, :slug, unique: true
  end
end
