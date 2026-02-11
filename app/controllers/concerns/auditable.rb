module Auditable
  extend ActiveSupport::Concern

  private

  def log_audit(action, contract: nil, details: nil)
    return unless Current.user && Current.organization

    AuditLog.create(
      organization: Current.organization,
      user: Current.user,
      contract: contract,
      action: action,
      details: details
    )
  rescue => e
    Rails.logger.error("Audit log failed: #{e.message}")
    Sentry.capture_exception(e) if Sentry.initialized?
  end
end
