class Admin::AuditLogsController < Admin::BaseController
  def index
    scope = AuditLog.includes(:organization, :user, :contract).order(created_at: :desc)
    scope = scope.where(organization_id: params[:organization_id]) if params[:organization_id].present?
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(action: params[:action_type]) if params[:action_type].present?

    if params[:start_date].present?
      start_date = parse_date(params[:start_date])
      scope = scope.where(created_at: start_date.beginning_of_day..) if start_date
    end

    if params[:end_date].present?
      end_date = parse_date(params[:end_date])
      scope = scope.where(created_at: ..end_date.end_of_day) if end_date
    end

    @pagy, @audit_logs = pagy(scope, limit: 50)
    @organizations = Organization.order(:name)
    @users = User.order(:email_address)
    @actions = AuditLog::ACTIONS
  end

  private

  def parse_date(value)
    Date.parse(value)
  rescue ArgumentError
    nil
  end
end
