class BackfillOrganizationContractsCount < ActiveRecord::Migration[8.1]
  def up
    Organization.find_each do |org|
      Organization.reset_counters(org.id, :contracts)
    end
  end

  def down
    # no-op
  end
end
