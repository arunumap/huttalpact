class Admin::JobsController < Admin::BaseController
  STATUSES = %w[all pending running scheduled failed completed].freeze

  def index
    @solid_queue_available = solid_queue_available?
    return unless @solid_queue_available

    @status_filter = params[:status].to_s.downcase
    @status_filter = "all" unless STATUSES.include?(@status_filter)
    @class_filter = params[:job_class].presence

    # Counts for tabs
    @counts = {
      all: SolidQueue::Job.count,
      pending: pending_job_ids.count,
      running: SolidQueue::ClaimedExecution.count,
      scheduled: SolidQueue::ScheduledExecution.count,
      failed: SolidQueue::FailedExecution.count,
      completed: SolidQueue::Job.where.not(finished_at: nil).count
    }

    # Build filtered scope
    @pagy, @jobs = pagy(filtered_jobs, limit: 50)

    # Preload execution associations for displayed jobs
    job_ids = @jobs.map(&:id)
    @failed_map = SolidQueue::FailedExecution.where(job_id: job_ids).index_by(&:job_id)
    @claimed_map = SolidQueue::ClaimedExecution.where(job_id: job_ids).index_by(&:job_id)
    @scheduled_map = SolidQueue::ScheduledExecution.where(job_id: job_ids).index_by(&:job_id)
    @ready_map = SolidQueue::ReadyExecution.where(job_id: job_ids).index_by(&:job_id)

    # Distinct job classes for the class filter dropdown
    @job_classes = SolidQueue::Job.distinct.pluck(:class_name).sort

    # Worker processes
    @processes = SolidQueue::Process.order(last_heartbeat_at: :desc).limit(50)
  end

  def show
    return redirect_to admin_jobs_path, alert: "Solid Queue is not available." unless solid_queue_available?

    @job = SolidQueue::Job.find(params[:id])
    @failed_execution = SolidQueue::FailedExecution.find_by(job_id: @job.id)
    @claimed_execution = SolidQueue::ClaimedExecution.find_by(job_id: @job.id)
    @scheduled_execution = SolidQueue::ScheduledExecution.find_by(job_id: @job.id)
  end

  def failed
    return redirect_to admin_jobs_path, alert: "Solid Queue is not available." unless solid_queue_available?

    @pagy, @failed_executions = pagy(SolidQueue::FailedExecution.includes(:job).order(created_at: :desc), limit: 50)
  end

  def recurring
    return redirect_to admin_jobs_path, alert: "Solid Queue is not available." unless solid_queue_available?

    @tasks = SolidQueue::RecurringTask.order(:key)
  end

  private

  def filtered_jobs
    scope = SolidQueue::Job.order(created_at: :desc)

    case @status_filter
    when "pending"
      scope = scope.where(id: pending_job_ids)
    when "running"
      scope = scope.where(id: SolidQueue::ClaimedExecution.select(:job_id))
    when "scheduled"
      scope = scope.where(id: SolidQueue::ScheduledExecution.select(:job_id))
    when "failed"
      scope = scope.where(id: SolidQueue::FailedExecution.select(:job_id))
    when "completed"
      scope = scope.where.not(finished_at: nil)
    end

    scope = scope.where(class_name: @class_filter) if @class_filter.present?
    scope
  end

  def pending_job_ids
    SolidQueue::ReadyExecution.select(:job_id)
  end

  def job_status(job)
    return "failed" if @failed_map[job.id]
    return "running" if @claimed_map[job.id]
    return "scheduled" if @scheduled_map[job.id]
    return "pending" if @ready_map[job.id]
    return "completed" if job.finished_at.present?

    "unknown"
  end
  helper_method :job_status

  def job_status_badge_class(status)
    case status
    when "failed"    then "bg-red-100 text-red-700"
    when "running"   then "bg-blue-100 text-blue-700"
    when "scheduled" then "bg-yellow-100 text-yellow-800"
    when "pending"   then "bg-amber-100 text-amber-700"
    when "completed" then "bg-green-100 text-green-700"
    else "bg-slate-100 text-slate-600"
    end
  end
  helper_method :job_status_badge_class
end
