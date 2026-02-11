class ResetMonthlyExtractionsJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(
      "ai_extractions_count > 0"
    ).find_each do |org|
      org.reset_monthly_extractions!
    end
  end
end
