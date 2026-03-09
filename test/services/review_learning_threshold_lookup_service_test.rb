require "test_helper"

class ReviewLearningThresholdLookupServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @period_start = Date.new(2026, 1, 1)
    @period_end = Date.new(2026, 6, 30)
  end

  test "prefers contract type recommendation when available" do
    create_recommendation(field_name: "title", contract_type: "__all__", threshold: 75)
    create_recommendation(field_name: "title", contract_type: "maintenance", threshold: 85)

    result = ReviewLearningThresholdLookupService.new(
      organization: @organization,
      field_name: "title",
      contract_type: "maintenance"
    ).call

    assert_equal 85, result[:threshold]
    assert_equal "field_contract_type", result[:source]
    assert_equal "recommended", result[:reason_code]
  end

  test "falls back to field-wide recommendation when contract type recommendation is missing" do
    create_recommendation(field_name: "title", contract_type: "__all__", threshold: 75)

    result = ReviewLearningThresholdLookupService.new(
      organization: @organization,
      field_name: "title",
      contract_type: "lease"
    ).call

    assert_equal 75, result[:threshold]
    assert_equal "field", result[:source]
  end

  test "returns default when no recommendation exists" do
    result = ReviewLearningThresholdLookupService.new(
      organization: @organization,
      field_name: "title",
      contract_type: "maintenance"
    ).call

    assert_equal 80, result[:threshold]
    assert_equal "default", result[:source]
    assert_equal "no_recommendation", result[:reason_code]
  end

  private

  def create_recommendation(field_name:, contract_type:, threshold:)
    ReviewLearningAggregate.create!(
      organization: @organization,
      aggregate_type: ReviewLearningThresholdRecommendationService::AGGREGATE_TYPE,
      period_start_date: @period_start,
      period_end_date: @period_end,
      dimension_key: "contract_type=#{contract_type}|field_name=#{field_name}|scope=#{scope_for(contract_type)}",
      sample_size: 50,
      source_version: 1,
      dimensions: {
        "field_name" => field_name,
        "contract_type" => contract_type,
        "scope" => scope_for(contract_type)
      },
      metrics: {
        "recommended_threshold" => threshold,
        "reason_code" => "recommended"
      }
    )
  end

  def scope_for(contract_type)
    contract_type == "__all__" ? "field" : "field_contract_type"
  end
end
