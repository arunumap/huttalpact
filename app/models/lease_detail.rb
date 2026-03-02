class LeaseDetail < ApplicationRecord
  belongs_to :contract

  LEASE_TYPES = %w[gross modified_gross nnn percentage].freeze
  CAM_CAP_TYPES = %w[cumulative non_cumulative none].freeze
  TI_DISBURSEMENT_TYPES = %w[lump_sum draw_schedule reimbursement].freeze

  validates :lease_type, inclusion: { in: LEASE_TYPES }, allow_blank: true
  validates :cam_cap_type, inclusion: { in: CAM_CAP_TYPES }, allow_blank: true
  validates :ti_disbursement_type, inclusion: { in: TI_DISBURSEMENT_TYPES }, allow_blank: true

  validates :rentable_sqft, numericality: { greater_than: 0 }, allow_nil: true
  validates :usable_sqft, numericality: { greater_than: 0 }, allow_nil: true
  validates :load_factor, numericality: { greater_than: 0 }, allow_nil: true
  validates :security_deposit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :parking_spaces, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :parking_monthly_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :free_rent_months, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  validates :percentage_rent_rate, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :percentage_rent_breakpoint, numericality: { greater_than: 0 }, allow_nil: true

  validates :cam_base_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cam_base_year, numericality: { only_integer: true, greater_than: 1900 }, allow_nil: true
  validates :cam_cap_percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :cam_reconciliation_month, inclusion: { in: 1..12 }, allow_nil: true
  validates :cam_controllable_cap, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

  validates :ti_allowance_psf, numericality: { greater_than: 0 }, allow_nil: true
  validates :ti_total_amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :ti_amortization_rate, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :ti_amortization_term_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def lease_type_label
    lease_type&.titleize&.gsub("_", " ")
  end

  def nnn?
    lease_type == "nnn"
  end

  def gross?
    lease_type == "gross"
  end

  def modified_gross?
    lease_type == "modified_gross"
  end

  def has_cam?
    cam_base_amount.present? || cam_base_year.present? || cam_cap_percentage.present?
  end

  def has_ti?
    ti_allowance_psf.present? || ti_total_amount.present?
  end

  def has_percentage_rent?
    percentage_rent_rate.present? || percentage_rent_breakpoint.present?
  end

  def cam_reconciliation_date(year = Date.current.year)
    return nil unless cam_reconciliation_month.present?
    Date.new(year, cam_reconciliation_month, 1)
  end

  def next_cam_reconciliation_date
    return nil unless cam_reconciliation_month.present?
    candidate = cam_reconciliation_date(Date.current.year)
    candidate <= Date.current ? cam_reconciliation_date(Date.current.year + 1) : candidate
  end

  def ti_days_remaining
    return nil unless ti_deadline.present?
    (ti_deadline - Date.current).to_i
  end

  def cam_cap_type_label
    cam_cap_type&.titleize&.gsub("_", " ")
  end

  def ti_disbursement_type_label
    ti_disbursement_type&.titleize&.gsub("_", " ")
  end

  # Annual rent per square foot — the standard CRE comparison metric
  # Prefers the current rent escalation period; falls back to contract.monthly_value
  def annual_rent_per_sqft
    return nil unless rentable_sqft&.positive?

    current = contract.current_rent
    annual = current&.base_rent_annual
    annual ||= contract.monthly_value.present? ? contract.monthly_value * 12 : nil
    return nil unless annual&.positive?

    (annual / rentable_sqft).round(2)
  end
end
