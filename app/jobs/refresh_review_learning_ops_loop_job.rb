class RefreshReviewLearningOpsLoopJob < ApplicationJob
  queue_as :default

  def perform(as_of_date = Date.current.iso8601,
    aggregate_lookback_days = ReviewLearningOpsLoopService::DEFAULT_AGGREGATE_LOOKBACK_DAYS,
    organization_id = nil)
    organization = find_organization(organization_id)
    return if organization_id.present? && organization.nil?

    ReviewLearningOpsLoopService.new(
      as_of_date: to_date(as_of_date),
      aggregate_lookback_days: aggregate_lookback_days,
      organization: organization
    ).call
  end

  private

  def to_date(value)
    return value if value.is_a?(Date)

    Date.iso8601(value.to_s)
  end

  def find_organization(organization_id)
    return if organization_id.blank?

    Organization.find_by(id: organization_id).tap do |organization|
      next if organization.present?

      Rails.logger.warn("Organization #{organization_id} not found, skipping review learning ops loop refresh")
    end
  end
end
