class Admin::HealthController < Admin::BaseController
  def show
    @database_connected = ActiveRecord::Base.connection.active?
    @rails_version = Rails.version
    @ruby_version = RUBY_VERSION
    @environment = Rails.env
    @sentry_initialized = Sentry.initialized?

    if solid_queue_available?
      @solid_queue_process_count = SolidQueue::Process.count
      @solid_queue_healthy_process_count = SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).count
      @solid_queue_failed_count = SolidQueue::FailedExecution.count
      @solid_queue_pending_count = SolidQueue::Job.where(finished_at: nil).count
    else
      @solid_queue_process_count = 0
      @solid_queue_healthy_process_count = 0
      @solid_queue_failed_count = 0
      @solid_queue_pending_count = 0
    end
  end
end
