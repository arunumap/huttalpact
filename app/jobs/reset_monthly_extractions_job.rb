class ResetMonthlyExtractionsJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(
      "ai_extractions_count > 0"
    ).find_each do |org|
      org.reset_monthly_extractions_if_needed!
    end
  end
end
