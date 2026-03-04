class Admin::AiUsageController < Admin::BaseController
  def index
    @start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
    @end_date = parse_date(params[:end_date]) || Date.current

    logs = AiUsageLog.in_period(@start_date.beginning_of_day, @end_date.end_of_day)
    logs = logs.by_org(params[:organization_id]) if params[:organization_id].present?

    @total_input_tokens = logs.sum(:input_tokens)
    @total_output_tokens = logs.sum(:output_tokens)
    @total_tokens = logs.sum(:total_tokens)
    @total_extractions = logs.count
    @success_count = logs.successful.count
    @failure_count = logs.failed.count
    @estimated_cost = AiUsageLog.total_cost(logs)
    @average_cost_per_extraction = if @total_extractions.positive?
      @estimated_cost / @total_extractions
    end
    @daily_usage = logs.group("DATE(created_at)").order("DATE(created_at) DESC").sum(:total_tokens)

    # Feedback analytics
    feedbacks = ExtractionFeedback.in_period(@start_date.beginning_of_day, @end_date.end_of_day)
    @feedback_count = feedbacks.count
    @positive_feedback_count = feedbacks.positive.count
    @negative_feedback_count = feedbacks.negative.count
    @feedback_positive_pct = @feedback_count > 0 ? (@positive_feedback_count.to_f / @feedback_count * 100).round(1) : nil

    # Stats by extraction mode
    @mode_stats = logs.group(:extraction_mode).select(
      "extraction_mode",
      "COUNT(*) AS total_count",
      "SUM(CASE WHEN success THEN 1 ELSE 0 END) AS success_count",
      "AVG(duration_ms) AS avg_duration_ms",
      "AVG(total_tokens) AS avg_tokens"
    )

    # Stats by config version
    @config_stats = logs.where.not(ai_extraction_config_id: nil)
      .joins(:ai_extraction_config)
      .group("ai_extraction_configs.extraction_type", "ai_extraction_configs.version", "ai_extraction_configs.ai_model")
      .select(
        "ai_extraction_configs.extraction_type",
        "ai_extraction_configs.version",
        "ai_extraction_configs.ai_model",
        "COUNT(*) AS total_count",
        "SUM(CASE WHEN ai_usage_logs.success THEN 1 ELSE 0 END) AS success_count",
        "AVG(ai_usage_logs.duration_ms) AS avg_duration_ms"
      )

    @pagy, @usage_logs = pagy(
      logs.includes(:organization, :contract, :ai_extraction_config).order(created_at: :desc),
      limit: 50
    )
    @organizations = Organization.order(:name)
  end

  private

  def parse_date(value)
    return if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end
end
