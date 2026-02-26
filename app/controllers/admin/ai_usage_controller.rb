class Admin::AiUsageController < Admin::BaseController
  def index
    @start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
    @end_date = parse_date(params[:end_date]) || Date.current

    logs = AiUsageLog.in_period(@start_date.beginning_of_day, @end_date.end_of_day)
    logs = logs.by_org(params[:organization_id]) if params[:organization_id].present?

    @total_input_tokens = logs.sum(:input_tokens)
    @total_output_tokens = logs.sum(:output_tokens)
    @total_tokens = logs.sum(:total_tokens)
    @success_count = logs.successful.count
    @failure_count = logs.failed.count
    @estimated_cost = AiUsageLog.total_cost(logs)
    @daily_usage = logs.group("DATE(created_at)").order("DATE(created_at) DESC").sum(:total_tokens)

    @pagy, @usage_logs = pagy(logs.includes(:organization, :contract).order(created_at: :desc), limit: 50)
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
