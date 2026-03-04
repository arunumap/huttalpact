class Admin::AdminUsersController < Admin::BaseController
  before_action :set_admin_user, only: %i[show edit update destroy]

  def index
    scope = AdminUser.order(created_at: :desc)

    if params[:q].present?
      query = "%#{AdminUser.sanitize_sql_like(params[:q])}%"
      scope = scope.where(
        "email_address ILIKE :query OR first_name ILIKE :query OR last_name ILIKE :query",
        query:
      )
    end

    @pagy, @admin_users = pagy(scope, limit: 25)
  end

  def show
    @sessions = @admin_user.admin_sessions.order(created_at: :desc).limit(20)
    @blog_posts = @admin_user.blog_posts.order(created_at: :desc).limit(20)
  end

  def new
    @admin_user = AdminUser.new
  end

  def create
    @admin_user = AdminUser.new(admin_user_params)

    if @admin_user.save
      redirect_to admin_admin_user_path(@admin_user), notice: "Admin user created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @admin_user.update(admin_user_update_params)
      redirect_to admin_admin_user_path(@admin_user), notice: "Admin user updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @admin_user == Current.admin_user
      redirect_to admin_admin_users_path, alert: "You cannot delete your own admin account while signed in."
      return
    end

    @admin_user.destroy
    redirect_to admin_admin_users_path, notice: "Admin user deleted."
  end

  private

  def set_admin_user
    @admin_user = AdminUser.find(params[:id])
  end

  def admin_user_params
    params.require(:admin_user).permit(
      :email_address,
      :first_name,
      :last_name,
      :password,
      :password_confirmation
    )
  end

  def admin_user_update_params
    attrs = admin_user_params
    return attrs if attrs[:password].present?

    attrs.except(:password, :password_confirmation)
  end
end
