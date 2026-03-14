class CalendarPreference < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :calendar_connection
  belongs_to :user
  belongs_to :organization

  ALL_CATEGORIES = Alert::ALERT_TYPES.freeze

  before_validation :normalize_enabled_categories

  validates :remote_calendar_id, presence: true
  validates :calendar_connection_id, uniqueness: true
  validate :enabled_categories_must_be_valid

  def sync_enabled?
    sync_enabled && calendar_connection&.active?
  end

  def category_enabled?(category)
    effective_categories.include?(category.to_s)
  end

  def effective_categories
    return ALL_CATEGORIES if enabled_categories.blank?
    enabled_categories & ALL_CATEGORIES
  end

  private

  def normalize_enabled_categories
    self.enabled_categories = Array(enabled_categories).map { |category| category.to_s.strip }.reject(&:blank?).uniq
  end

  def enabled_categories_must_be_valid
    return if enabled_categories.blank?

    invalid = enabled_categories - ALL_CATEGORIES
    if invalid.any?
      errors.add(:enabled_categories, "contains invalid categories: #{invalid.join(', ')}")
    end
  end
end
