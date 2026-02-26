class Admin::UsersController < Admin::BaseController
  def index
    scope = User.order(created_at: :desc)

    if params[:q].present?
      query = "%#{User.sanitize_sql_like(params[:q])}%"
      scope = scope.where(
        "email_address ILIKE :query OR first_name ILIKE :query OR last_name ILIKE :query",
        query:
      )
    end

    @pagy, @users = pagy(scope, limit: 25)
  end

  def show
    @user = User.find(params[:id])
    @memberships = @user.memberships.includes(:organization).order(created_at: :desc)
    @sessions = @user.sessions.order(created_at: :desc).limit(20)
    @recent_activity = AuditLog.where(user_id: @user.id).includes(:organization, :contract).order(created_at: :desc).limit(20)
  end
end
