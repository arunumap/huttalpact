class RenameModelNameOnAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    rename_column :ai_usage_logs, :model_name, :ai_model
  end
end
