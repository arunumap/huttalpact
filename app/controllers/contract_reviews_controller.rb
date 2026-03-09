class ContractReviewsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_contract
  before_action :set_review

  def show
    @document_text = build_document_text
    @grouped_fields = build_grouped_fields
    @needs_review_fields = @review.fields.needs_review.pending.ordered
    @confident_fields = @review.fields.confident.pending.ordered
    @reviewed_fields_list = @review.fields.reviewed.ordered

    # Mark review as in_progress if still pending
    @review.update!(status: "in_progress") if @review.pending?
  end

  def update_field
    field = @review.fields.find(params[:field_id])

    case params[:decision]
    when "confirm"
      field.update!(
        status: "confirmed",
        reviewed_at: Time.current,
        reviewed_by: Current.user
      )
    when "edit"
      field.update!(
        status: "edited",
        user_value: params[:user_value],
        reviewed_at: Time.current,
        reviewed_by: Current.user
      )
    when "not_found"
      field.update!(
        status: "not_found",
        reviewed_at: Time.current,
        reviewed_by: Current.user
      )
    when "not_applicable"
      field.update!(
        status: "not_applicable",
        reviewed_at: Time.current,
        reviewed_by: Current.user
      )
    end

    @review.update!(reviewed_fields: @review.fields.reviewed.count)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "review_progress",
            partial: "contract_reviews/progress",
            locals: { review: @review }
          ),
          turbo_stream.replace(
            "review_panel",
            partial: "contract_reviews/review_panel",
            locals: { review: @review, contract: @contract }
          )
        ]
      end
      format.html { redirect_to contract_contract_review_path(@contract) }
    end
  end

  def bulk_accept
    count = @review.fields.confident.pending.update_all(
      status: "auto_accepted",
      reviewed_at: Time.current,
      reviewed_by_id: Current.user.id
    )

    @review.update!(reviewed_fields: @review.fields.reviewed.count)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "review_panel",
          partial: "contract_reviews/review_panel",
          locals: { review: @review, contract: @contract }
        )
      end
      format.html { redirect_to contract_contract_review_path(@contract), notice: "#{count} confident fields accepted." }
    end
  end

  def complete
    service = ContractReviewCompletionService.new(review: @review, user: Current.user)
    service.call

    redirect_to @contract, notice: "Review completed! Contract is now active."
  rescue ContractReviewCompletionService::ReviewIncompleteError => e
    redirect_to contract_contract_review_path(@contract), alert: e.message
  end

  def save_draft
    # Just acknowledge — fields are already saved via update_field
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "review_progress",
          partial: "contract_reviews/progress",
          locals: { review: @review, flash_message: "Progress saved." }
        )
      end
      format.html { redirect_to contract_contract_review_path(@contract), notice: "Progress saved." }
    end
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end

  def set_review
    @review = @contract.current_review
    unless @review
      redirect_to @contract, alert: "No active review found for this contract."
    end
  end

  def build_document_text
    @contract.contract_documents
      .where(extraction_status: "completed")
      .order(:position)
      .map { |doc| { id: doc.id, name: doc.file.filename.to_s, text: doc.extracted_text } }
  end

  def build_grouped_fields
    groups = @review.fields.ordered.group_by(&:field_group)
    ReviewFieldCatalog::FIELD_GROUPS.filter_map do |group_key|
      fields = groups[group_key]
      next if fields.blank?

      {
        key: group_key,
        label: ReviewFieldCatalog::FIELD_GROUP_LABELS[group_key],
        fields: fields
      }
    end
  end
end
