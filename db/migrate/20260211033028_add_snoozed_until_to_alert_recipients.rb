class AddSnoozedUntilToAlertRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :alert_recipients, :snoozed_until, :date
  end
end
