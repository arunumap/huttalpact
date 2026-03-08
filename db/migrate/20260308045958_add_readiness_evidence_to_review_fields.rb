class AddReadinessEvidenceToReviewFields < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_review_fields, :confidence_score, :integer
    add_column :contract_review_fields, :source_quality_flag, :string
    add_column :contract_review_fields, :readiness_reasons, :text, array: true, default: [], null: false
  end
end
