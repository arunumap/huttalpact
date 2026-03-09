require "test_helper"

class ReviewLearningAggregateTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @aggregate = build_aggregate
  end

  test "valid aggregate is valid" do
    assert @aggregate.valid?
  end

  test "requires aggregate_type" do
    @aggregate.aggregate_type = nil

    assert_not @aggregate.valid?
    assert_includes @aggregate.errors[:aggregate_type], "can't be blank"
  end

  test "requires dimension_key" do
    @aggregate.dimension_key = nil

    assert_not @aggregate.valid?
    assert_includes @aggregate.errors[:dimension_key], "can't be blank"
  end

  test "sample_size must be a non-negative integer" do
    @aggregate.sample_size = -1
    assert_not @aggregate.valid?

    @aggregate.sample_size = 1.5
    assert_not @aggregate.valid?
  end

  test "source_version must be a positive integer" do
    @aggregate.source_version = 0
    assert_not @aggregate.valid?

    @aggregate.source_version = 1.5
    assert_not @aggregate.valid?
  end

  test "period end must be on or after period start" do
    @aggregate.period_start_date = Date.current
    @aggregate.period_end_date = Date.yesterday

    assert_not @aggregate.valid?
    assert_includes @aggregate.errors[:period_end_date], "must be on or after period start date"
  end

  test "dimensions and metrics must be JSON objects" do
    @aggregate.dimensions = "bad"
    @aggregate.metrics = []

    assert_not @aggregate.valid?
    assert_includes @aggregate.errors[:dimensions], "must be a JSON object"
    assert_includes @aggregate.errors[:metrics], "must be a JSON object"
  end

  test "dimension_key must be unique within aggregate window" do
    create_aggregate
    duplicate = build_aggregate

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:dimension_key], "has already been taken"
  end

  test "for_type scope filters by aggregate type" do
    wanted = create_aggregate
    create_aggregate(aggregate_type: "confidence_calibration_daily", dimension_key: "confidence:70-79")

    scoped = ReviewLearningAggregate.for_type("field_outcome_daily")

    assert_equal [ wanted.id ], scoped.pluck(:id)
  end

  test "for_period scope filters by period start date" do
    in_range = create_aggregate(period_start_date: Date.new(2026, 3, 1), period_end_date: Date.new(2026, 3, 1))
    create_aggregate(
      period_start_date: Date.new(2026, 1, 1),
      period_end_date: Date.new(2026, 1, 1),
      dimension_key: "field:vendor_name:service_agreement"
    )

    scoped = ReviewLearningAggregate.for_period(Date.new(2026, 2, 1), Date.new(2026, 3, 31))

    assert_equal [ in_range.id ], scoped.pluck(:id)
  end

  test "for_field scope filters by field_name dimension" do
    title = create_aggregate
    create_aggregate(
      dimension_key: "field:vendor_name:service_agreement",
      dimensions: {
        "field_name" => "vendor_name",
        "contract_type" => "service_agreement",
        "review_type" => "full"
      }
    )

    scoped = ReviewLearningAggregate.for_field("title")

    assert_equal [ title.id ], scoped.pluck(:id)
  end

  test "dimension and metric helpers return string-keyed values" do
    aggregate = create_aggregate(
      dimensions: { "field_name" => "monthly_value" },
      metrics: { "corrected_rate" => 0.35 }
    )

    assert_equal "monthly_value", aggregate.dimension(:field_name)
    assert_equal 0.35, aggregate.metric(:corrected_rate)
  end

  private

  def build_aggregate(overrides = {})
    ReviewLearningAggregate.new(
      {
        organization: @organization,
        aggregate_type: "field_outcome_daily",
        period_start_date: Date.new(2026, 3, 10),
        period_end_date: Date.new(2026, 3, 10),
        dimension_key: "field:title:service_agreement",
        sample_size: 12,
        source_version: 1,
        last_event_at: Time.current,
        dimensions: {
          "field_name" => "title",
          "contract_type" => "service_agreement",
          "review_type" => "full"
        },
        metrics: {
          "corrected_rate" => 0.25,
          "average_confidence" => 82.1
        }
      }.merge(overrides)
    )
  end

  def create_aggregate(overrides = {})
    aggregate = build_aggregate(overrides)
    aggregate.save!
    aggregate
  end
end
