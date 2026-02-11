class CleanStaleDraftsJob < ApplicationJob
  queue_as :default

  # Delete draft contracts that haven't been updated in 7 days
  STALE_THRESHOLD = 7.days

  def perform
    stale_drafts = Contract.draft.where(updated_at: ...STALE_THRESHOLD.ago)
    count = stale_drafts.count

    stale_drafts.destroy_all

    Rails.logger.info("CleanStaleDraftsJob: Deleted #{count} stale draft contracts") if count > 0
  end
end
