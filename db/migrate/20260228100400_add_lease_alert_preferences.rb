class AddLeaseAlertPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :alert_preferences, :days_before_option_exercise, :integer, default: 90
    add_column :alert_preferences, :days_before_rent_escalation, :integer, default: 30
    add_column :alert_preferences, :days_before_cam_reconciliation, :integer, default: 30
    add_column :alert_preferences, :days_before_milestone, :integer, default: 14
  end
end
