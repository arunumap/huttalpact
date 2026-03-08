class ContractReviewsController < ApplicationController
  before_action :set_contract
  before_action :set_review, except: :show

  def show
    @review = @contract.review_workspace
    raise ActiveRecord::RecordNotFound if @review.blank? && !@contract.draft?
  end

  def save_progress
    ContractReviewActionService.new(review: @review, user: Current.user).save_progress!
    redirect_to contract_review_path(@contract), notice: "Review progress saved."
  rescue ContractReviewActionService::ActionError => e
    redirect_to contract_review_path(@contract), alert: e.message
  end

  def bulk_confirm_safe_items
    count = ContractReviewActionService.new(review: @review, user: Current.user).bulk_confirm_safe_items!
    message = count.positive? ? "Confirmed #{count} safe #{'field'.pluralize(count)}." : "There were no safe fields left to confirm."
    redirect_to contract_review_path(@contract), notice: message
  rescue ContractReviewActionService::ActionError => e
    redirect_to contract_review_path(@contract), alert: e.message
  end

  def complete
    completion = ContractReviewCompletionService.new(review: @review, user: Current.user).call
    follow_through_count = completion.activation_result&.skipped ? @review.standard_priority_open_items_summary[:count] : @review.reload.standard_priority_open_items_summary[:count]
    notice = "Review completed."
    notice = "#{notice} #{follow_through_count} standard-priority #{'item'.pluralize(follow_through_count)} remain open." if follow_through_count.positive?
    redirect_to contract_path(@contract), notice:
  rescue ContractReviewCompletionService::CompletionError => e
    redirect_to contract_review_path(@contract), alert: e.message
  end

  private

  def set_contract
    @contract = Current.organization.contracts.find(params[:contract_id])
  end

  def set_review
    @review = @contract.review_workspace
    raise ActiveRecord::RecordNotFound if @review.blank?
  end
end
