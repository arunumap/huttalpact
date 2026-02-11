class CreateContractDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_documents, id: :uuid do |t|
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.text :extracted_text
      t.string :extraction_status, default: "pending", null: false
      t.integer :page_count
      t.timestamps
    end

    add_index :contract_documents, [ :contract_id, :created_at ]
  end
end
