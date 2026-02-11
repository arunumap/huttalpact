class PagesController < ApplicationController
  allow_unauthenticated_access
  prepend_before_action :resume_session

  layout "marketing"

  def home
    redirect_to dashboard_path if authenticated?
  end
end
