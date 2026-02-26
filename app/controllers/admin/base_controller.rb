class Admin::BaseController < ActionController::Base
  include AdminAuthentication
  include Pagy::Backend

  allow_browser versions: :modern
  stale_when_importmap_changes

  layout "admin"

  before_action :set_admin_sentry_context

  helper_method :current_admin

  private

  def current_admin
    Current.admin_user
  end

  def set_admin_sentry_context
    return unless Sentry.initialized?
    return unless Current.admin_user

    Sentry.set_user(id: Current.admin_user.id, email: Current.admin_user.email_address)
    Sentry.set_tags(admin: true)
  end

  def solid_queue_available?
    return false unless defined?(SolidQueue::Job)

    SolidQueue::Job.connection.data_source_exists?(SolidQueue::Job.table_name)
  rescue ActiveRecord::ActiveRecordError
    false
  end
end
