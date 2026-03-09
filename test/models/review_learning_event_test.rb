require "test_helper"

class ReviewLearningEventTest < ActiveSupport::TestCase
  setup do
    @field = contract_review_fields(:vendor_name_field)
    @event = build_event_for(@field)
  end

  test "valid event is valid" do
    assert @event.valid?
  end

  test "decision must be a reviewed outcome" do
    @event.decision = "pending"

    assert_not @event.valid?
    assert_includes @event.errors[:decision], "is not included in the list"
  end

  test "contract_type allows unknown for uncategorized rows" do
    @event.contract_type = "unknown"

    assert @event.valid?
  end

  test "contract_type must be known" do
    @event.contract_type = "master_service"

    assert_not @event.valid?
    assert_includes @event.errors[:contract_type], "is not included in the list"
  end

  test "confidence must be between 0 and 100" do
    @event.confidence = -1
    assert_not @event.valid?

    @event.confidence = 101
    assert_not @event.valid?
  end

  test "confidence_threshold must be between 0 and 100" do
    @event.confidence_threshold = -1
    assert_not @event.valid?

    @event.confidence_threshold = 101
    assert_not @event.valid?
  end

  test "source_match_strategy must be supported when present" do
    @event.source_match_strategy = "vector"

    assert_not @event.valid?
    assert_includes @event.errors[:source_match_strategy], "is not included in the list"
  end

  test "evidence_quality must be valid" do
    @event.evidence_quality = "excellent"

    assert_not @event.valid?
    assert_includes @event.errors[:evidence_quality], "is not included in the list"
  end

  test "metadata columns must be JSON objects" do
    @event.field_metadata = "not-an-object"
    @event.review_metadata = []

    assert_not @event.valid?
    assert_includes @event.errors[:field_metadata], "must be a JSON object"
    assert_includes @event.errors[:review_metadata], "must be a JSON object"
  end

  test "enforces one event per review field" do
    create_event_for(@field)
    duplicate = build_event_for(@field)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:contract_review_field_id], "has already been taken"
  end

  test "review and field references must be consistent" do
    @event.contract_review = contract_reviews(:pending_review)

    assert_not @event.valid?
    assert_includes @event.errors[:contract_review_id], "must belong to the same contract"
    assert_includes @event.errors[:contract_review_field_id], "must belong to the specified review"
  end

  test "source_document must belong to the same contract" do
    @event.source_document = contract_documents(:completed_doc)

    assert_not @event.valid?
    assert_includes @event.errors[:source_document_id], "must belong to the same contract"
  end

  test "accepted scope returns accepted decisions only" do
    confirmed = create_event_for(contract_review_fields(:vendor_name_field))
    auto_accepted = create_event_for(contract_review_fields(:auto_accepted_field))
    create_event_for(contract_review_fields(:start_date_field), corrected: true)

    accepted = ReviewLearningEvent.accepted

    assert_includes accepted, confirmed
    assert_includes accepted, auto_accepted
    assert_equal 2, accepted.count
  end

  test "corrected scope returns corrected outcomes only" do
    unchanged = create_event_for(contract_review_fields(:vendor_name_field))
    corrected = create_event_for(contract_review_fields(:start_date_field), corrected: true)

    scoped = ReviewLearningEvent.corrected

    assert_includes scoped, corrected
    assert_not_includes scoped, unchanged
  end

  test "for_field scope filters by field_name" do
    vendor_event = create_event_for(contract_review_fields(:vendor_name_field))
    create_event_for(contract_review_fields(:start_date_field), corrected: true)

    scoped = ReviewLearningEvent.for_field("vendor_name")

    assert_equal [ vendor_event.id ], scoped.pluck(:id)
  end

  private

  def build_event_for(field, overrides = {})
    review = field.contract_review
    contract = review.contract

    ReviewLearningEvent.new(
      {
        organization: review.organization,
        contract:,
        contract_review: review,
        contract_review_field: field,
        reviewed_by: users(:one),
        review_type: review.review_type,
        contract_type: contract.contract_type.presence || "unknown",
        field_name: field.field_name,
        field_group: field.field_group,
        decision: field.status == "pending" ? "confirmed" : field.status,
        confidence: field.confidence,
        confidence_threshold: review.confidence_threshold,
        needs_review: field.needs_review,
        corrected: field.status.in?(%w[edited not_found not_applicable]),
        extracted_value: field.extracted_value,
        final_value: field.final_value,
        user_value: field.user_value,
        source_excerpt: field.source_excerpt,
        source_match_strategy: field.source_match_strategy,
        source_excerpt_present: field.source_excerpt.present?,
        source_locator: field.source_locator || {},
        evidence_quality: field.source_excerpt.present? ? "strong" : "missing",
        evidence_quality_score: field.source_excerpt.present? ? 90 : nil,
        field_metadata: {
          "display_name" => field.display_name,
          "position" => field.position
        },
        review_metadata: {
          "review_status" => review.status
        },
        reviewed_at: field.reviewed_at || Time.current
      }.merge(overrides)
    )
  end

  def create_event_for(field, overrides = {})
    event = build_event_for(field, overrides)
    event.save!
    event
  end
end
