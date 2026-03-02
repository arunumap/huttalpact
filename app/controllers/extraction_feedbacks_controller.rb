class ExtractionFeedbacksController < ApplicationController
  before_action :set_contract

  def create
    @feedback = ExtractionFeedback.find_or_initialize_by(
      contract: @contract,
      user: Current.user,
      organization: Current.organization
    )

    @feedback.assign_attributes(feedback_params)

    # Link to the most recent successful usage log for this contract
    @feedback.ai_usage_log ||= @contract.ai_usage_logs.successful.order(created_at: :desc).first

    if @feedback.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to contract_path(@contract), notice: "Thanks for your feedback!" }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("extraction_feedback", partial: "extraction_feedbacks/form", locals: { contract: @contract, feedback: @feedback }) }
        format.html { redirect_to contract_path(@contract), alert: "Could not save feedback." }
      end
    end
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end

  def feedback_params
    params.require(:extraction_feedback).permit(:rating, :comment)
  end
end
