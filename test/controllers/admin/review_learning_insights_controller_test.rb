require "test_helper"

class Admin::ReviewLearningInsightsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    @organization = organizations(:one)
  end

  test "requires admin authentication" do
    get admin_review_learning_insights_path

    assert_redirected_to new_admin_session_path
  end

  test "shows learning metrics, calibration summary, and worst-performing fields" do
    sign_in_as_admin(@admin_user)

    today = Date.current
    older_date = today - 90.days

    create_outcome_aggregate(
      date: today,
      contract_type: "lease",
      field_name: "title",
      sample_size: 10,
      corrected_count: 2,
      error_count: 2
    )
    create_outcome_aggregate(
      date: today,
      contract_type: "lease",
      field_name: "monthly_value",
      sample_size: 5,
      corrected_count: 3,
      error_count: 3
    )
    create_outcome_aggregate(
      date: older_date,
      contract_type: "lease",
      field_name: "title",
      sample_size: 40,
      corrected_count: 40,
      error_count: 40
    )

    create_calibration_aggregate(
      date: today,
      contract_type: "lease",
      field_name: "title",
      confidence_bucket: "90-99",
      sample_size: 10,
      observed_agreement_rate: 0.8,
      expected_agreement_rate: 0.9
    )
    create_calibration_aggregate(
      date: today,
      contract_type: "lease",
      field_name: "monthly_value",
      confidence_bucket: "60-69",
      sample_size: 5,
      observed_agreement_rate: 0.4,
      expected_agreement_rate: 0.65
    )
    create_calibration_aggregate(
      date: older_date,
      contract_type: "lease",
      field_name: "monthly_value",
      confidence_bucket: "90-99",
      sample_size: 50,
      observed_agreement_rate: 1.0,
      expected_agreement_rate: 1.0
    )

    get admin_review_learning_insights_path

    assert_response :success
    assert_select "h2", text: "Review Learning Insights"
    assert_select "#learning-overall-volume p.text-2xl", text: "15"
    assert_select "#learning-correction-rate p.text-2xl", text: "33.3%"
    assert_select "#learning-error-rate p.text-2xl", text: "33.3%"
    assert_select "#review-learning-ops-loop h3", text: "Operational Improvement Loop"
    assert_select "#review-learning-ops-loop", text: /recommendations are advisory only/i
    assert_select "h3", text: "Confidence Calibration Summary"
    assert_select "#learning-observed-agreement dd", text: "66.7%"
    assert_select "#learning-expected-agreement dd", text: "81.7%"
    assert_select "#learning-calibration-gap dd", text: "-15.0%"
    assert_select "h3", text: "Worst-performing Fields"
    assert_select "td", text: "Monthly Value"
    assert_select "td", text: "Title"
  end

  test "applies contract type and field filters" do
    sign_in_as_admin(@admin_user)

    today = Date.current

    create_outcome_aggregate(
      date: today,
      contract_type: "lease",
      field_name: "title",
      sample_size: 10,
      corrected_count: 1,
      error_count: 1
    )
    create_outcome_aggregate(
      date: today,
      contract_type: "service_agreement",
      field_name: "vendor_name",
      sample_size: 10,
      corrected_count: 6,
      error_count: 6
    )

    create_calibration_aggregate(
      date: today,
      contract_type: "lease",
      field_name: "title",
      confidence_bucket: "80-89",
      sample_size: 10,
      observed_agreement_rate: 0.9,
      expected_agreement_rate: 0.85
    )
    create_calibration_aggregate(
      date: today,
      contract_type: "service_agreement",
      field_name: "vendor_name",
      confidence_bucket: "80-89",
      sample_size: 10,
      observed_agreement_rate: 0.5,
      expected_agreement_rate: 0.85
    )

    get admin_review_learning_insights_path, params: {
      start_date: today.to_s,
      end_date: today.to_s,
      contract_type: "lease",
      field_name: "title"
    }

    assert_response :success
    assert_select "#learning-overall-volume p.text-2xl", text: "10"
    assert_select "#learning-correction-rate p.text-2xl", text: "10.0%"
    assert_select "td", text: "Title"
    assert_select "td", text: "Vendor Name", count: 0
    assert_select "select[name='field_name'] option", text: "Vendor Name", count: 0
  end

  private

  def create_outcome_aggregate(date:, contract_type:, field_name:, sample_size:, corrected_count:, error_count:)
    create_aggregate(
      aggregate_type: ReviewLearningAggregationService::FIELD_OUTCOME_AGGREGATE_TYPE,
      date:,
      sample_size:,
      dimensions: {
        "field_name" => field_name,
        "contract_type" => contract_type,
        "review_type" => "full",
        "model_name" => "claude-sonnet-4",
        "model_version" => "1",
        "source_type" => "locator",
        "source_match_strategy" => "exact"
      },
      metrics: {
        "corrected_count" => corrected_count,
        "error_count" => error_count
      }
    )
  end

  def create_calibration_aggregate(
    date:,
    contract_type:,
    field_name:,
    confidence_bucket:,
    sample_size:,
    observed_agreement_rate:,
    expected_agreement_rate:
  )
    confidence_min, confidence_max = confidence_bucket.split("-").map(&:to_i)

    create_aggregate(
      aggregate_type: ReviewLearningAggregationService::CONFIDENCE_CALIBRATION_AGGREGATE_TYPE,
      date:,
      sample_size:,
      dimensions: {
        "field_name" => field_name,
        "contract_type" => contract_type,
        "review_type" => "full",
        "model_name" => "claude-sonnet-4",
        "model_version" => "1",
        "source_type" => "locator",
        "source_match_strategy" => "exact",
        "confidence_bucket" => confidence_bucket,
        "confidence_min" => confidence_min,
        "confidence_max" => confidence_max
      },
      metrics: {
        "observed_agreement_rate" => observed_agreement_rate,
        "expected_agreement_rate" => expected_agreement_rate
      }
    )
  end

  def create_aggregate(aggregate_type:, date:, sample_size:, dimensions:, metrics:)
    ReviewLearningAggregate.create!(
      organization: @organization,
      aggregate_type: aggregate_type,
      period_start_date: date,
      period_end_date: date,
      dimension_key: "#{aggregate_type}-#{SecureRandom.uuid}",
      sample_size: sample_size,
      source_version: 1,
      last_event_at: date.end_of_day,
      dimensions: dimensions,
      metrics: metrics
    )
  end
end
