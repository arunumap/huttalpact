class ReviewAlertActivationService
  Result = Struct.new(:created_count, :total_count, :skipped, keyword_init: true)

  def initialize(contract:, review:, user: nil)
    @contract = contract
    @review = review
    @user = user
  end

  def call
    unless @contract.alert_generation_enabled?
      create_audit!("review_alerts_skipped", "Skipped alert regeneration because the contract status is #{@contract.status}.")
      return Result.new(created_count: 0, total_count: @contract.alerts.count, skipped: true)
    end

    prior_ids = @contract.alerts.pluck(:id)

    ActiveRecord::Base.transaction do
      AlertGeneratorService.new(@contract).call
    end

    total_count = @contract.alerts.count
    created_count = @contract.alerts.where.not(id: prior_ids).count

    create_audit!(
      "review_alerts_activated",
      "Activated approved review data and regenerated #{total_count} #{'alert'.pluralize(total_count)} for #{@review.review_trigger.humanize.downcase}."
    )

    Result.new(created_count:, total_count:, skipped: false)
  end

  private

  def create_audit!(action, details)
    AuditLog.create!(organization: @contract.organization, user: @user, contract: @contract, action:, details:)
  end
end
