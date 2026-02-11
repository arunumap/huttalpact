class AuditLogsController < ApplicationController
  def index
    audit_logs = AuditLog.includes(:user, :contract).recent

    audit_logs = audit_logs.for_action(params[:action_type]) if params[:action_type].present?
    audit_logs = audit_logs.for_contract(params[:contract_id]) if params[:contract_id].present?

    @audit_log_days_limit = current_organization.plan_audit_log_days
    audit_logs = audit_logs.since(current_organization.audit_log_cutoff_date)

    @pagy, @audit_logs = pagy(audit_logs, limit: 25)
  end
end
