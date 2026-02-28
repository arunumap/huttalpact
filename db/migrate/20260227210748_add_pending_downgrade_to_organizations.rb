class AddPendingDowngradeToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :pending_plan, :string
    add_column :organizations, :pending_plan_interval, :string
    add_column :organizations, :pending_plan_effective_at, :datetime
    add_column :organizations, :pending_downgrade_schedule_id, :string
    add_index :organizations, :pending_plan_effective_at
  end
end
