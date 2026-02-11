class CreateKeyClauses < ActiveRecord::Migration[8.1]
  def change
    create_table :key_clauses, id: :uuid do |t|
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.string :clause_type, null: false
      t.text :content
      t.string :page_reference
      t.integer :confidence_score
      t.timestamps
    end

    add_index :key_clauses, [ :contract_id, :clause_type ]
  end
end
