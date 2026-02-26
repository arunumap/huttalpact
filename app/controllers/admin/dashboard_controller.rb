class Admin::DashboardController < Admin::BaseController
  def show
    ai_logs_scope = AiUsageLog.since(30.days.ago)

    @total_users = User.count
    @total_organizations = Organization.count
    @total_contracts = Contract.count
    @total_documents = ContractDocument.count
    @total_storage_bytes = ActiveStorage::Blob.sum(:byte_size)
    @active_user_sessions = Session.active.count
    @active_admin_sessions = AdminSession.active.count
    @plan_distribution = Organization.group(:plan).count
    @ai_log_count_30d = ai_logs_scope.count
    @failed_ai_logs_30d = ai_logs_scope.failed.count
    @ai_input_tokens_30d = ai_logs_scope.sum(:input_tokens)
    @ai_output_tokens_30d = ai_logs_scope.sum(:output_tokens)
    @ai_estimated_cost_30d = AiUsageLog.total_cost(ai_logs_scope)

    if solid_queue_available?
      @pending_jobs = SolidQueue::Job.where(finished_at: nil).count
      @failed_jobs = SolidQueue::FailedExecution.count
      @running_jobs = SolidQueue::ClaimedExecution.count
      @healthy_workers = SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).count
    else
      @pending_jobs = 0
      @failed_jobs = 0
      @running_jobs = 0
      @healthy_workers = 0
    end

    @recent_audit_logs = AuditLog.includes(:organization, :user).order(created_at: :desc).limit(8)
  end
end
