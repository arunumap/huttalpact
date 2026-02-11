class EnhanceMultiDocumentExtraction < ActiveRecord::Migration[8.1]
  def change
    # === contract_documents: add document_type and position ===
    add_column :contract_documents, :document_type, :string, default: "main_contract", null: false
    add_column :contract_documents, :position, :integer, default: 0, null: false
    add_index :contract_documents, [ :contract_id, :position ]

    # === key_clauses: add source_document_id FK with cascade delete ===
    add_reference :key_clauses, :source_document,
                  type: :uuid,
                  null: true,
                  foreign_key: { to_table: :contract_documents, on_delete: :cascade },
                  index: true

    # === contracts: add last_changes_summary for incremental extraction audit ===
    add_column :contracts, :last_changes_summary, :text

    # === Upgrade existing FKs to use ON DELETE CASCADE ===
    remove_foreign_key :key_clauses, :contracts
    add_foreign_key :key_clauses, :contracts, on_delete: :cascade

    remove_foreign_key :contract_documents, :contracts
    add_foreign_key :contract_documents, :contracts, on_delete: :cascade
  end
end
