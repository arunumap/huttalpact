# frozen_string_literal: true

module ReviewGuard
  extend ActiveSupport::Concern

  private

  def block_if_in_review
    return unless @contract&.in_review?

    respond_to do |format|
      format.turbo_stream { head :forbidden }
      format.html do
        redirect_to contract_contract_review_path(@contract),
          alert: "This contract is in review. Complete the review before making changes."
      end
    end
  end
end
