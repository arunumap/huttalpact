class DailyAlertCheckJob < ApplicationJob
  queue_as :default

  def perform
    Alert.pending.due_on_or_before(Date.current).find_each do |alert|
      AlertDeliveryService.new(alert).call
    rescue => e
      Rails.logger.error("Failed to deliver alert #{alert.id}: #{e.message}")
    end
  end
end
