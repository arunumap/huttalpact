class ReviewLearningAggregate < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :organization

  validates :aggregate_type, presence: true
  validates :period_start_date, presence: true
  validates :period_end_date, presence: true
  validates :dimension_key, presence: true,
                            uniqueness: { scope: %i[organization_id aggregate_type period_start_date period_end_date] }
  validates :sample_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_version, numericality: { only_integer: true, greater_than: 0 }
  validate :period_bounds_are_valid
  validate :dimensions_must_be_object
  validate :metrics_must_be_object

  scope :for_type, ->(aggregate_type) { where(aggregate_type:) }
  scope :for_period, ->(start_date, end_date) { where(period_start_date: start_date..end_date) }
  scope :for_field, ->(field_name) { where("dimensions ->> 'field_name' = ?", field_name) }
  scope :recent_first, -> { order(period_start_date: :desc, updated_at: :desc) }

  def dimension(name)
    dimensions[name.to_s]
  end

  def metric(name)
    metrics[name.to_s]
  end

  private

  def period_bounds_are_valid
    return if period_start_date.blank? || period_end_date.blank?
    return if period_end_date >= period_start_date

    errors.add(:period_end_date, "must be on or after period start date")
  end

  def dimensions_must_be_object
    return if dimensions.is_a?(Hash)

    errors.add(:dimensions, "must be a JSON object")
  end

  def metrics_must_be_object
    return if metrics.is_a?(Hash)

    errors.add(:metrics, "must be a JSON object")
  end
end
