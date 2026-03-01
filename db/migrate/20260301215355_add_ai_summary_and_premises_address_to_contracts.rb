class AddAiSummaryAndPremisesAddressToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :ai_summary, :text
    add_column :contracts, :premises_address, :string
    add_index :contracts, :premises_address
  end
end
