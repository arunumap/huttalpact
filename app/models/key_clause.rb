class KeyClause < ApplicationRecord
  belongs_to :contract
  belongs_to :contract_document, foreign_key: :source_document_id, optional: true

  CLAUSE_TYPES = %w[
    termination
    renewal
    penalty
    sla
    price_escalation
    liability
    insurance_requirement
  ].freeze

  validates :clause_type, presence: true, inclusion: { in: CLAUSE_TYPES }
  validates :content, presence: true
  validates :confidence_score, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }, allow_nil: true

  scope :high_confidence, -> { where("confidence_score >= 80") }
  scope :by_type, ->(type) { where(clause_type: type) }

  def clause_type_label
    clause_type.titleize.gsub("_", " ")
  end

  def confidence_level
    return nil unless confidence_score
    case confidence_score
    when 80..100 then :high
    when 50..79  then :medium
    else :low
    end
  end
end
