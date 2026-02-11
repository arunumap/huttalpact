class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :inviter, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :email, null: false
      t.string :role, null: false, default: "member"
      t.string :token, null: false
      t.datetime :accepted_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, [ :organization_id, :email ]
    add_index :invitations, [ :organization_id, :accepted_at ]
  end
end
