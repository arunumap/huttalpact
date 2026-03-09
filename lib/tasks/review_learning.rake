namespace :review_learning do
  desc "Refresh review learning aggregates/recommendations for the continuous ops loop"
  task :refresh, [ :as_of_date, :aggregate_lookback_days, :organization_id ] => :environment do |_task, args|
    resolve_organization = lambda do |organization_id|
      next if organization_id.blank?

      Organization.find_by(id: organization_id).tap do |organization|
        next if organization.present?

        warn "Organization #{organization_id} not found; no refresh executed."
      end
    end

    as_of_date = args[:as_of_date].present? ? Date.iso8601(args[:as_of_date]) : Date.current
    aggregate_lookback_days = args[:aggregate_lookback_days].presence ||
      ReviewLearningOpsLoopService::DEFAULT_AGGREGATE_LOOKBACK_DAYS
    organization = resolve_organization.call(args[:organization_id])
    next if args[:organization_id].present? && organization.nil?

    summaries = ReviewLearningOpsLoopService.new(
      as_of_date: as_of_date,
      aggregate_lookback_days: aggregate_lookback_days,
      organization: organization
    ).call

    puts "Refreshed review learning ops loop for #{summaries.size} organization(s) as of #{as_of_date}."
    summaries.each do |summary|
      puts(
        "- #{summary[:organization_id]}: refreshed #{summary[:refreshed_dates_count]} aggregate day(s), " \
          "#{summary[:recommendation_count]} recommendation row(s)"
      )
    end
  rescue ArgumentError => error
    abort "Invalid arguments: #{error.message}"
  end
end
