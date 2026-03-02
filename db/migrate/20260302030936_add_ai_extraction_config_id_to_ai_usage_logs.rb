class AddAiExtractionConfigIdToAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    add_reference :ai_usage_logs, :ai_extraction_config, type: :uuid, foreign_key: true
  end
end
