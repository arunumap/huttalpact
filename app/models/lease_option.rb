class LeaseOption < ApplicationRecord
  belongs_to :contract
  has_many :calendar_event_syncs, as: :source, dependent: :destroy

  OPTION_TYPES = %w[renewal expansion termination purchase rofr rofo].freeze

  validates :option_type, presence: true, inclusion: { in: OPTION_TYPES }
  validates :term_length_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :penalty_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  default_scope { order(position: :asc, notice_deadline: :asc) }

  scope :upcoming, -> { unscoped.where("notice_deadline > ?", Date.current).order(notice_deadline: :asc) }
  scope :expired, -> { unscoped.where("notice_deadline < ?", Date.current).order(notice_deadline: :asc) }
  scope :by_type, ->(type) { where(option_type: type) }

  def option_type_label
    case option_type
    when "rofr" then "Right of First Refusal"
    when "rofo" then "Right of First Offer"
    else option_type&.titleize
    end
  end

  def days_until_notice_deadline
    return nil unless notice_deadline.present?
    (notice_deadline - Date.current).to_i
  end

  def days_until_exercise_deadline
    return nil unless exercise_deadline.present?
    (exercise_deadline - Date.current).to_i
  end

  def notice_deadline_passed?
    notice_deadline.present? && notice_deadline < Date.current
  end

  def urgent?
    notice_deadline.present? && !notice_deadline_passed? && days_until_notice_deadline <= 90
  end

  def term_length_label
    return nil unless term_length_months.present?
    if term_length_months >= 12 && (term_length_months % 12).zero?
      years = term_length_months / 12
      "#{years} #{"year".pluralize(years)}"
    else
      "#{term_length_months} #{"month".pluralize(term_length_months)}"
    end
  end
end
