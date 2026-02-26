class Admin::OrganizationsController < Admin::BaseController
  def index
    scope = Organization.order(created_at: :desc)
    scope = scope.where(plan: params[:plan]) if params[:plan].present?

    if params[:q].present?
      query = "%#{Organization.sanitize_sql_like(params[:q])}%"
      scope = scope.where("name ILIKE :query OR slug ILIKE :query", query:)
    end

    @pagy, @organizations = pagy(scope, limit: 25)
  end

  def show
    @organization = Organization.find(params[:id])
    @memberships = @organization.memberships.includes(:user).order(created_at: :desc)
    @recent_contracts = @organization.contracts.order(created_at: :desc).limit(10)
    @recent_ai_usage = AiUsageLog.by_org(@organization.id).order(created_at: :desc).limit(10)
    @pending_invitations = @organization.invitations.pending.order(created_at: :desc)
    @recent_activity = AuditLog.where(organization_id: @organization.id).includes(:user, :contract).order(created_at: :desc).limit(20)
  end
end
