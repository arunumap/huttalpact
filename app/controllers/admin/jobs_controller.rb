class Admin::JobsController < Admin::BaseController
  def index
    @solid_queue_available = solid_queue_available?
    return unless @solid_queue_available

    @pending_jobs = SolidQueue::Job.where(finished_at: nil).count
    @failed_jobs = SolidQueue::FailedExecution.count
    @running_jobs = SolidQueue::ClaimedExecution.count
    @scheduled_jobs = SolidQueue::ScheduledExecution.count
    @processes = SolidQueue::Process.order(last_heartbeat_at: :desc).limit(50)
  end

  def show
    return redirect_to failed_admin_jobs_path, alert: "Solid Queue is not available." unless defined?(SolidQueue::FailedExecution)

    @failed_execution = SolidQueue::FailedExecution.find(params[:id])
    @job = @failed_execution.job
  end

  def failed
    return redirect_to admin_jobs_path, alert: "Solid Queue is not available." unless defined?(SolidQueue::FailedExecution)

    @pagy, @failed_executions = pagy(SolidQueue::FailedExecution.includes(:job).order(created_at: :desc), limit: 50)
  end

  def recurring
    return redirect_to admin_jobs_path, alert: "Solid Queue is not available." unless defined?(SolidQueue::RecurringTask)

    @tasks = SolidQueue::RecurringTask.order(:key)
  end
end
