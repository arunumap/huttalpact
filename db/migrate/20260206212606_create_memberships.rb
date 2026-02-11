class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.string :role, default: "member", null: false

      t.timestamps
    end
    add_index :memberships, [ :user_id, :organization_id ], unique: true
  end
end
