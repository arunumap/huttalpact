class AddRequestTimeoutToAiExtractionConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_extraction_configs, :request_timeout, :integer
  end
end
