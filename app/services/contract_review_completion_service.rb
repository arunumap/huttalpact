class ContractReviewCompletionService
  class CompletionError < StandardError; end

  attr_reader :activation_result

  def initialize(review:, user:)
    @review = review
    @user = user
    @contract = review.contract
  end

  def call
    raise CompletionError, "Only open reviews can be completed." unless @review.open?

    blocking_fields = @review.contract_review_fields.blocked.pending_review.where.not(source_type: "app_managed")
    if blocking_fields.exists?
      raise CompletionError, "Resolve #{blocking_fields.count} blocking #{'item'.pluralize(blocking_fields.count)} before completing review."
    end

    ActiveRecord::Base.transaction do
      ContractReviewCanonicalApplier.new(@review).call
      transition_contract_status!
      @review.update!(status: "completed", completed_at: Time.current)
      create_audit!
      @activation_result = ReviewAlertActivationService.new(contract: @contract, review: @review, user: @user).call
    end

    self
  rescue ActiveRecord::RecordInvalid => e
    friendly_errors = e.record.errors.map do |error|
      attribute = error.attribute.to_s.titleize.tr("_", " ")
      case error.type
      when :inclusion
        options = e.record.class.validators_on(error.attribute)
                    .find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
                    &.options&.dig(:in)
        if options.present?
          "#{attribute} must be one of: #{Array(options).map { |o| o.to_s.titleize.tr('_', ' ') }.join(', ')}"
        else
          "#{attribute} has an invalid value"
        end
      else
        "#{attribute} #{error.message}"
      end
    end
    raise CompletionError, "Cannot complete review: #{friendly_errors.to_sentence}"
  end

  private

  def transition_contract_status!
    @contract.update!(status: completed_contract_status)
  end

  def completed_contract_status
    return "expired" if @contract.end_date.present? && @contract.end_date <= Date.current
    return "expiring_soon" if @contract.end_date.present? && @contract.end_date <= Date.current + 30.days

    "active"
  end

  def create_audit!
    follow_through_count = @review.standard_priority_open_items_summary[:count]
    details = "Completed human review and returned the contract to #{@contract.status.gsub('_', ' ')}."
    details = "#{details} #{follow_through_count} standard-priority #{'item'.pluralize(follow_through_count)} remain open for follow-through." if follow_through_count.positive?

    AuditLog.create!(
      organization: @contract.organization,
      user: @user,
      contract: @contract,
      action: "review_completed",
      details:
    )
  end
end
