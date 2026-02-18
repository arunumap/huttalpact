module RequireAdminAccess
  extend ActiveSupport::Concern

  private

  def require_admin_access
    membership = current_membership
    return if membership&.admin_or_owner?

    redirect_to root_path, alert: "You need admin or owner access to manage team settings."
  end

  def current_membership
    @current_membership ||= current_organization&.memberships&.find_by(user: Current.user)
  end
end
