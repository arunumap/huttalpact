class ReviewLearningOpsLoopService
  DEFAULT_AGGREGATE_LOOKBACK_DAYS = 30
  MIN_AGGREGATE_LOOKBACK_DAYS = 1
  MAX_AGGREGATE_LOOKBACK_DAYS = 90

  def initialize(as_of_date: Date.current, aggregate_lookback_days: DEFAULT_AGGREGATE_LOOKBACK_DAYS,
    organization: nil, logger: Rails.logger)
    @as_of_date = as_of_date.to_date
    @aggregate_lookback_days = normalize_aggregate_lookback_days(aggregate_lookback_days)
    @organization = organization
    @logger = logger
  end

  def call
    organizations_scope.find_each.with_object([]) do |organization, summaries|
      summaries << refresh_for_organization(organization)
    rescue StandardError => error
      logger.error(
        "ReviewLearningOpsLoopService failed for organization=#{organization.id}: " \
          "#{error.class}: #{error.message}"
      )
      raise if @organization.present?
    end
  end

  private

  attr_reader :logger

  def organizations_scope
    return Organization.where(id: @organization.id) if @organization.present?

    Organization.where(id: ReviewLearningEvent.select(:organization_id).distinct)
  end

  def refresh_for_organization(organization)
    refreshed_dates = reviewed_dates_for(organization)
    refreshed_dates.each do |reviewed_on|
      ReviewLearningAggregationService.new(
        organization: organization,
        period_start_date: reviewed_on
      ).call
    end

    recommendation_rows = ReviewLearningThresholdRecommendationService.new(
      organization: organization,
      as_of_date: @as_of_date
    ).call

    summary = {
      organization_id: organization.id,
      as_of_date: @as_of_date,
      aggregate_lookback_days: @aggregate_lookback_days,
      refreshed_dates_count: refreshed_dates.size,
      recommendation_count: recommendation_rows.size
    }

    logger.info(
      "ReviewLearningOpsLoopService refreshed organization=#{organization.id} " \
        "dates=#{refreshed_dates.size} recommendations=#{recommendation_rows.size} as_of=#{@as_of_date}"
    )

    summary
  end

  def reviewed_dates_for(organization)
    ReviewLearningEvent
      .where(organization_id: organization.id, reviewed_at: aggregate_time_range)
      .distinct
      .pluck(Arel.sql("DATE(reviewed_at)"))
      .compact
      .map(&:to_date)
      .sort
  end

  def aggregate_time_range
    aggregate_period_start.beginning_of_day..@as_of_date.end_of_day
  end

  def aggregate_period_start
    @aggregate_period_start ||= @as_of_date - (@aggregate_lookback_days - 1).days
  end

  def normalize_aggregate_lookback_days(value)
    days = value.to_i
    days = DEFAULT_AGGREGATE_LOOKBACK_DAYS if days <= 0
    days.clamp(MIN_AGGREGATE_LOOKBACK_DAYS, MAX_AGGREGATE_LOOKBACK_DAYS)
  end
end
