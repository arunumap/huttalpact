class RentEscalation < ApplicationRecord
  belongs_to :contract

  ESCALATION_TYPES = %w[fixed_percentage cpi fmv_reset stepped flat].freeze

  validates :effective_date, presence: true
  validates :escalation_type, presence: true, inclusion: { in: ESCALATION_TYPES }
  validates :base_rent_monthly, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :base_rent_annual, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :escalation_value, numericality: true, allow_nil: true

  default_scope { order(effective_date: :asc) }

  scope :future, -> { where("effective_date > ?", Date.current) }
  scope :past_or_current, -> { where("effective_date <= ?", Date.current) }

  def current?
    effective_date <= Date.current &&
      contract.rent_escalations.where("effective_date > ? AND effective_date <= ?", effective_date, Date.current).none?
  end

  def escalation_type_label
    escalation_type&.titleize&.gsub("_", " ")
  end

  def escalation_description
    case escalation_type
    when "fixed_percentage"
      escalation_value.present? ? "#{escalation_value}% increase" : "Fixed percentage"
    when "cpi"
      "CPI-indexed"
    when "fmv_reset"
      "Fair market value reset"
    when "stepped"
      escalation_value.present? ? "Step to #{number_with_delimiter(escalation_value)}" : "Stepped increase"
    when "flat"
      "No change"
    else
      description.presence || "—"
    end
  end

  private

  def number_with_delimiter(number)
    ActionController::Base.helpers.number_with_delimiter(number)
  end
end
