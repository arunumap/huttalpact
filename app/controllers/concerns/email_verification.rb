module EmailVerification
  extend ActiveSupport::Concern

  included do
    before_action :require_email_verification
  end

  class_methods do
    def allow_unverified_access(**options)
      skip_before_action :require_email_verification, **options
    end
  end

  private

  def require_email_verification
    return unless Current.user
    return if Current.user.email_verified?

    redirect_to email_verification_path
  end
end
