require "test_helper"

class ReviewLearningIngestionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @organization = organizations(:one)
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    @source_document = contract_documents(:completed_doc)

    @contract.contract_reviews.destroy_all

    ActsAsTenant.with_tenant(@organization) do
      @review = @contract.contract_reviews.create!(
        organization: @organization,
        status: "completed",
        review_type: "full",
        confidence_threshold: 80,
        total_fields: 0,
        reviewed_fields: 0,
        completed_at: Time.current,
        completed_by: @user
      )
    end
  end

  test "ingests one event per reviewed outcome with normalized payloads" do
    confirmed = create_field("vendor_name", "core", '"Acme Properties"', status: "confirmed", confidence: 92)
    edited = create_field("start_date", "dates", '"2025-01-01"', status: "edited", confidence: 66, user_value: '"2025-01-15"')
    not_found = create_field("total_value", "financial", nil, status: "not_found", confidence: nil)
    not_applicable = create_field("renewal_term", "financial", nil, status: "not_applicable", confidence: nil)
    refresh_review_counts!

    assert_difference "ReviewLearningEvent.count", 4 do
      ingest!
    end

    events = ReviewLearningEvent.where(contract_review: @review).index_by(&:field_name)
    assert_equal %w[confirmed edited not_applicable not_found], events.values.map(&:decision).sort

    confirmed_event = events.fetch("vendor_name")
    assert_equal @organization.id, confirmed_event.organization_id
    assert_equal @contract.id, confirmed_event.contract_id
    assert_equal @review.id, confirmed_event.contract_review_id
    assert_equal confirmed.id, confirmed_event.contract_review_field_id
    assert_equal "string", confirmed_event.field_metadata["field_type"]
    assert_equal "accepted", confirmed_event.review_metadata["correctness_signal"]
    assert_equal false, confirmed_event.corrected
    assert_equal confirmed.extracted_value, confirmed_event.final_value

    edited_event = events.fetch("start_date")
    assert_equal true, edited_event.corrected
    assert_equal edited.user_value, edited_event.final_value
    assert_equal "corrected", edited_event.review_metadata["correctness_signal"]
    assert_equal "edited", edited_event.review_metadata["correction_type"]

    assert_nil events.fetch("total_value").final_value
    assert_nil events.fetch("renewal_term").final_value
    assert_equal true, events.fetch("total_value").corrected
    assert_equal true, events.fetch("renewal_term").corrected
  end

  test "propagates confidence and evidence details to learning events" do
    grounded = create_field(
      "title",
      "core",
      '"Office Lease Agreement"',
      status: "confirmed",
      confidence: 88,
      source_excerpt: "This Office Lease Agreement...",
      source_match_strategy: "exact",
      source_locator: {
        "document_id" => @source_document.id,
        "start_offset" => 10,
        "end_offset" => 38,
        "matched_text" => "Office Lease Agreement"
      }
    )
    broad = create_field(
      "vendor_name",
      "core",
      '"Acme Properties"',
      status: "edited",
      confidence: 55,
      user_value: '"Acme Properties LLC"',
      source_excerpt: "Acme Properties LLC"
    )
    missing = create_field("notice_period_days", "financial", nil, status: "not_found", confidence: nil)
    refresh_review_counts!

    ingest!

    grounded_event = grounded.reload.learning_event
    assert_equal 88, grounded_event.confidence
    assert_equal "exact", grounded_event.source_match_strategy
    assert_equal true, grounded_event.source_excerpt_present
    assert_equal "strong", grounded_event.evidence_quality
    assert_equal 95, grounded_event.evidence_quality_score
    assert_equal @source_document.id, grounded_event.source_locator["document_id"]
    assert_equal "grounded", grounded_event.field_metadata["evidence_status"]

    broad_event = broad.reload.learning_event
    assert_equal "moderate", broad_event.evidence_quality
    assert_equal 75, broad_event.evidence_quality_score
    assert_equal true, broad_event.source_excerpt_present
    assert_equal({}, broad_event.source_locator)
    assert_equal "broad", broad_event.field_metadata["evidence_status"]

    missing_event = missing.reload.learning_event
    assert_equal "missing", missing_event.evidence_quality
    assert_nil missing_event.evidence_quality_score
    assert_equal false, missing_event.source_excerpt_present
    assert_equal({}, missing_event.source_locator)
    assert_equal "missing", missing_event.field_metadata["evidence_status"]
  end

  test "is idempotent for repeated completion ingestion context" do
    field = create_field("title", "core", '"Office Lease Agreement"', status: "confirmed", confidence: 90)
    refresh_review_counts!

    assert_difference "ReviewLearningEvent.count", 1 do
      ingest!
    end
    event_id = field.reload.learning_event.id

    assert_no_difference "ReviewLearningEvent.count" do
      ingest!
    end

    assert_equal event_id, field.reload.learning_event.id
  end

  test "enqueues aggregate refresh jobs for reviewed event dates" do
    day_one = Time.zone.parse("2026-03-10 09:00:00")
    day_two = Time.zone.parse("2026-03-11 09:00:00")
    create_field("title", "core", '"Office Lease Agreement"', status: "confirmed", confidence: 92, reviewed_at: day_one)
    create_field("start_date", "dates", '"2026-03-10"', status: "edited", confidence: 61, reviewed_at: day_two)
    refresh_review_counts!
    clear_enqueued_jobs

    assert_enqueued_jobs 2, only: RefreshReviewLearningAggregatesJob do
      ingest!
    end

    aggregate_jobs = enqueued_jobs.select { |job| job["job_class"] == "RefreshReviewLearningAggregatesJob" }
    queued_dates = aggregate_jobs.map { |job| job["arguments"].second }.sort

    assert_equal [ day_one.to_date.iso8601, day_two.to_date.iso8601 ], queued_dates
  end

  private

  def ingest!
    ActsAsTenant.with_tenant(@organization) do
      ReviewLearningIngestionService.new(review: @review).call
    end
  end

  def create_field(field_name, field_group, extracted_value, status:, confidence:, user_value: nil,
    source_excerpt: nil, source_locator: nil, source_match_strategy: nil, reviewed_at: Time.current)
    definition = ReviewFieldCatalog.find(field_name)

    @review.fields.create!(
      field_name: field_name,
      field_group: field_group,
      display_name: definition&.display_name || field_name.humanize,
      extracted_value: extracted_value,
      confidence: confidence,
      source_excerpt: source_excerpt,
      source_locator: source_locator,
      source_match_strategy: source_match_strategy,
      needs_review: confidence.nil? || confidence < @review.confidence_threshold,
      status: status,
      user_value: user_value,
      reviewed_at: reviewed_at,
      reviewed_by: @user,
      source_document: @source_document,
      position: @review.fields.count
    )
  end

  def refresh_review_counts!
    @review.update!(
      total_fields: @review.fields.count,
      reviewed_fields: @review.fields.reviewed.count
    )
  end
end
