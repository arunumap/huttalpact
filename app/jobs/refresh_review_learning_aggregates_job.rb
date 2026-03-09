class RefreshReviewLearningAggregatesJob < ApplicationJob
  queue_as :default

  def perform(organization_id, period_start_date, period_end_date = nil)
    organization = Organization.find(organization_id)
    parsed_period_start = to_date(period_start_date)
    parsed_period_end = period_end_date.present? ? to_date(period_end_date) : nil

    ReviewLearningAggregationService.new(
      organization: organization,
      period_start_date: parsed_period_start,
      period_end_date: parsed_period_end
    ).call

    ReviewLearningThresholdRecommendationService.new(
      organization: organization,
      as_of_date: parsed_period_end || parsed_period_start
    ).call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Organization #{organization_id} not found, skipping review learning aggregate refresh")
  end

  private

  def to_date(value)
    value.is_a?(Date) ? value : Date.iso8601(value.to_s)
  end
end
