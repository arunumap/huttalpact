class AddAiExtractionTrackingToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :ai_extractions_count, :integer, default: 0, null: false
    add_column :organizations, :ai_extractions_reset_at, :datetime
  end
end
