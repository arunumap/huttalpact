class CleanOrphanedUsersJob < ApplicationJob
  queue_as :default

  def perform
    deleted_count = 0

    User.without_organizations.find_each do |user|
      OrphanedUserDeletionService.new(user).delete!
      deleted_count += 1
    end

    Rails.logger.info("CleanOrphanedUsersJob: Deleted #{deleted_count} orphaned users") if deleted_count.positive?
  end
end
