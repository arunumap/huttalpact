class AddDirectionToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :direction, :string, default: "outbound", null: false
    add_index :contracts, :direction
  end
end
