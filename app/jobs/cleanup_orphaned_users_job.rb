class CleanupOrphanedUsersJob < ApplicationJob
  queue_as :default

  ORPHAN_RETENTION_PERIOD = 60.days

  def perform
    User.where.not(orphaned_at: nil)
        .where(orphaned_at: ...ORPHAN_RETENTION_PERIOD.ago)
        .find_each do |user|
      next if user.memberships.exists?

      user.sessions.destroy_all
      user.destroy!
      Rails.logger.info("CleanupOrphanedUsersJob: destroyed orphaned user #{user.id} (#{user.email_address})")
    end
  end
end
