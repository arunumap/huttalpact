class ContractReviewFieldsController < ApplicationController
  before_action :set_contract
  before_action :set_review
  before_action :set_field

  def confirm
    action_service.confirm!(field: @field, note: params[:review_note])
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), notice: "Field confirmed."
  rescue ContractReviewActionService::ActionError => e
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), alert: e.message
  end

  def update
    action_service.edit!(field: @field, raw_value: field_params[:approved_value], note: field_params[:review_note])
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), notice: "Field updated."
  rescue ContractReviewActionService::ActionError => e
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), alert: e.message
  end

  def mark_not_found
    action_service.mark_not_found!(field: @field, note: params[:review_note])
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), notice: "Field marked not found."
  rescue ContractReviewActionService::ActionError => e
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), alert: e.message
  end

  def mark_not_applicable
    action_service.mark_not_applicable!(field: @field, note: params[:review_note])
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), notice: "Field marked not applicable."
  rescue ContractReviewActionService::ActionError => e
    redirect_to contract_review_path(@contract, anchor: view_context.dom_id(@field)), alert: e.message
  end

  private

  def set_contract
    @contract = Current.organization.contracts.find(params[:contract_id])
  end

  def set_review
    @review = @contract.review_workspace
    raise ActiveRecord::RecordNotFound if @review.blank?
  end

  def set_field
    @field = @review.contract_review_fields.find(params[:id])
  end

  def field_params
    params.require(:contract_review_field).permit(:approved_value, :review_note)
  end

  def action_service
    @action_service ||= ContractReviewActionService.new(review: @review, user: Current.user)
  end
end
