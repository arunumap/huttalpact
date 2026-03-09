class Admin::ReviewLearningInsightsController < Admin::BaseController
  def show
    @insights = Admin::ReviewLearningInsightsPresenter.new(params: filter_params)
    @overview = @insights.overview
    @calibration_summary = @insights.calibration_summary
    @calibration_buckets = @insights.calibration_buckets
    @worst_fields = @insights.worst_fields
    @contract_type_options = @insights.contract_type_options
    @field_options = @insights.field_options
  end

  private

  def filter_params
    params.permit(:start_date, :end_date, :contract_type, :field_name)
  end
end
