class LeaseMilestone < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :contract
  belongs_to :organization
  has_many :calendar_event_syncs, as: :source, dependent: :destroy

  MILESTONE_TYPES = %w[
    cam_reconciliation
    insurance_renewal
    estoppel_response
    ti_completion
    percentage_rent_report
    guarantee_burnoff
    custom
  ].freeze

  RECURRENCE_INTERVALS = %w[monthly quarterly annual].freeze

  validates :milestone_type, presence: true, inclusion: { in: MILESTONE_TYPES }
  validates :due_date, presence: true
  validates :recurrence_interval, inclusion: { in: RECURRENCE_INTERVALS }, allow_blank: true

  default_scope { order(due_date: :asc) }

  scope :upcoming, -> { where("due_date >= ?", Date.current) }
  scope :overdue, -> { where("due_date < ?", Date.current) }
  scope :by_type, ->(type) { where(milestone_type: type) }
  scope :recurring, -> { where(recurring: true) }

  def milestone_type_label
    milestone_type&.titleize&.gsub("_", " ")
  end

  def days_until_due
    return nil unless due_date.present?
    (due_date - Date.current).to_i
  end

  def overdue?
    due_date < Date.current
  end

  def urgent?
    !overdue? && days_until_due.present? && days_until_due <= 30
  end

  def next_occurrence_date
    return due_date unless recurring? && recurrence_interval.present? && due_date < Date.current

    candidate = due_date
    while candidate < Date.current
      candidate = advance_date(candidate)
    end
    candidate
  end

  private

  def advance_date(date)
    case recurrence_interval
    when "monthly"   then date + 1.month
    when "quarterly" then date + 3.months
    when "annual"    then date + 1.year
    else date + 1.year
    end
  end
end
