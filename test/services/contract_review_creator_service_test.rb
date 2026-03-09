require "test_helper"

class ContractReviewCreatorServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    # Clear any existing reviews from fixtures
    @contract.contract_reviews.destroy_all
  end

  # --- Full mode with field_metadata ---

  test "full mode creates review with confidence scores, excerpts, and reasoning from metadata" do
    extracted = build_generic_extraction.merge("field_metadata" => {
      "title" => { "confidence" => 95, "source_excerpt" => "Title is HVAC Agreement", "reasoning" => "Found in header" },
      "vendor_name" => { "confidence" => 88, "source_excerpt" => "CoolAir Services LLC", "reasoning" => "Party B identified" },
      "monthly_value" => { "confidence" => 60, "source_excerpt" => "$1,200/mo", "reasoning" => "Low confidence due to ambiguity" }
    })

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert_equal "pending", review.status
    assert_equal "full", review.review_type
    assert_equal 80, review.confidence_threshold

    title_field = review.fields.find_by(field_name: "title")
    assert_equal 95, title_field.confidence
    assert_equal "Title is HVAC Agreement", title_field.source_excerpt
    assert_equal "Found in header", title_field.reasoning
    assert_equal false, title_field.needs_review # 95 >= 80

    low_conf_field = review.fields.find_by(field_name: "monthly_value")
    assert_equal 60, low_conf_field.confidence
    assert_equal true, low_conf_field.needs_review # 60 < 80
  end

  # --- Full mode without field_metadata ---

  test "full mode without metadata sets nil confidence and needs_review true for all fields" do
    extracted = build_generic_extraction

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    review.fields.each do |field|
      assert_nil field.confidence, "Expected nil confidence for #{field.field_name}"
      assert field.needs_review, "Expected needs_review=true for #{field.field_name}"
    end
  end

  test "needs_review field without source_excerpt backfills excerpt from document text" do
    extracted = {
      "title" => "HVAC Maintenance Agreement",
      "field_metadata" => {
        "title" => { "confidence" => 60, "reasoning" => "Title inferred from opening paragraph." }
      }
    }

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    field = review.fields.find_by!(field_name: "title")
    assert field.needs_review?
    assert field.source_excerpt.present?
    assert_includes field.source_excerpt, "HVAC Maintenance Agreement"
    assert_equal "exact", field.source_match_strategy
    assert field.source_locator.present?
  end

  test "needs_review field without inferable excerpt adds manual verification guidance" do
    extracted = {
      "title" => "ZXQ-UNMATCHED-CITATION-STRING",
      "field_metadata" => {
        "title" => { "confidence" => 55, "reasoning" => "Inferred from context." }
      }
    }

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    field = review.fields.find_by!(field_name: "title")
    assert field.needs_review?
    assert_nil field.source_excerpt
    assert_includes field.reasoning, "Source excerpt unavailable"
  end

  # --- Lease contract creates lease-specific fields ---

  test "lease contract creates all lease-specific fields" do
    lease_contract = contracts(:commercial_lease)
    lease_contract.contract_reviews.destroy_all
    extracted = build_lease_extraction

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: lease_contract, extracted_data: extracted, mode: :full).call
    end

    lease_only_groups = %w[lease_space cam ti escalations options milestones]
    lease_only_groups.each do |group|
      assert review.fields.where(field_group: group).exists?,
        "Expected fields in group '#{group}' for lease contract"
    end

    assert review.fields.find_by(field_name: "rent_escalations").present?
    assert review.fields.find_by(field_name: "lease_options").present?
    assert review.fields.find_by(field_name: "lease_milestones").present?
  end

  # --- Non-lease contract excludes lease-specific fields ---

  test "non-lease contract only creates generic fields" do
    extracted = build_generic_extraction

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    lease_only_fields = ReviewFieldCatalog::FIELDS.select(&:lease_only).map(&:field_name)
    review.fields.each do |field|
      refute_includes lease_only_fields, field.field_name,
        "Non-lease contract should not have lease-only field '#{field.field_name}'"
    end
  end

  # --- Incremental mode ---

  test "incremental mode only creates fields where AI value differs from canonical" do
    @contract.update!(title: "HVAC Maintenance - Building A", vendor_name: "CoolAir Services")

    extracted = {
      "title" => "HVAC Maintenance - Building A", # same
      "vendor_name" => "New Vendor Corp" # different
    }

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :incremental).call
    end

    assert_nil review.fields.find_by(field_name: "title"), "Should skip field with same value"
    assert review.fields.find_by(field_name: "vendor_name").present?, "Should include field with different value"
  end

  # --- Sets contract status to in_review ---

  test "sets contract status to in_review" do
    @contract.update!(status: "active")
    extracted = build_generic_extraction

    ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert_equal "in_review", @contract.reload.status
  end

  test "does not change status if already in_review" do
    @contract.update!(status: "in_review")
    extracted = build_generic_extraction

    ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert_equal "in_review", @contract.reload.status
  end

  # --- Cancels existing active review ---

  test "completes existing active reviews before creating new one" do
    existing_review = ActsAsTenant.with_tenant(@organization) do
      @contract.contract_reviews.create!(
        organization: @organization,
        status: "pending",
        review_type: "full",
        confidence_threshold: 80
      )
    end

    extracted = build_generic_extraction

    new_review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert_equal "completed", existing_review.reload.status
    assert_equal "pending", new_review.status
    refute_equal existing_review.id, new_review.id
  end

  test "locks contract while replacing active review" do
    existing_review = ActsAsTenant.with_tenant(@organization) do
      @contract.contract_reviews.create!(
        organization: @organization,
        status: "pending",
        review_type: "full",
        confidence_threshold: 80
      )
    end
    extracted = build_generic_extraction
    lock_called = false

    ActsAsTenant.with_tenant(@organization) do
      @contract.stub(:lock!, -> { lock_called = true }) do
        ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
      end
    end

    assert lock_called
    assert_equal "completed", existing_review.reload.status
    assert_equal 1, @contract.contract_reviews.active.count
  end

  # --- JSON-encodes extracted values ---

  test "JSON-encodes string, number, boolean, and array extracted values" do
    extracted = build_generic_extraction.merge(
      "auto_renews" => true,
      "monthly_value" => 1500.50,
      "key_clauses" => [ { "clause_type" => "termination", "content" => "30 day notice" } ]
    )

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    title_field = review.fields.find_by(field_name: "title")
    assert_equal '"Test Contract"', title_field.extracted_value

    auto_renews_field = review.fields.find_by(field_name: "auto_renews")
    assert_equal "true", auto_renews_field.extracted_value

    monthly_field = review.fields.find_by(field_name: "monthly_value")
    assert_equal "1500.5", monthly_field.extracted_value

    clauses_field = review.fields.find_by(field_name: "key_clauses")
    parsed = JSON.parse(clauses_field.extracted_value)
    assert_kind_of Array, parsed
    assert_equal "termination", parsed.first["clause_type"]
  end

  # --- Handles nil values ---

  test "skips fields with nil extracted values in full mode" do
    extracted = { "title" => "Test", "vendor_name" => nil, "start_date" => "2025-01-01" }

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert_nil review.fields.find_by(field_name: "vendor_name"), "Should skip nil value in full mode"
    assert review.fields.find_by(field_name: "title").present?
  end

  # --- Confidence threshold ---

  test "fields below 80 confidence get needs_review true" do
    extracted = build_generic_extraction.merge("field_metadata" => {
      "title" => { "confidence" => 79 },
      "vendor_name" => { "confidence" => 80 },
      "start_date" => { "confidence" => 81 }
    })

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert review.fields.find_by(field_name: "title").needs_review, "79 < 80 should need review"
    refute review.fields.find_by(field_name: "vendor_name").needs_review, "80 >= 80 should not need review"
    refute review.fields.find_by(field_name: "start_date").needs_review, "81 >= 80 should not need review"
  end

  # --- Source locator ---

  test "stores page_hint and section_hint in source_locator jsonb" do
    extracted = build_generic_extraction.merge("field_metadata" => {
      "title" => { "confidence" => 90, "page_hint" => 1, "section_hint" => "Article I" }
    })

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    field = review.fields.find_by(field_name: "title")
    assert_equal({ "page_hint" => 1, "section_hint" => "Article I" }, field.source_locator)
  end

  test "source_locator is nil when no page or section hints provided" do
    extracted = build_generic_extraction.merge("field_metadata" => {
      "title" => { "confidence" => 90 }
    })

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    field = review.fields.find_by(field_name: "title")
    assert_nil field.source_locator
  end

  # --- Total fields count ---

  test "review total_fields matches actual field count" do
    extracted = build_generic_extraction

    review = ActsAsTenant.with_tenant(@organization) do
      ContractReviewCreatorService.new(contract: @contract, extracted_data: extracted, mode: :full).call
    end

    assert_equal review.fields.count, review.total_fields
    assert review.total_fields > 0
  end

  private

  def build_generic_extraction
    {
      "title" => "Test Contract",
      "vendor_name" => "Test Vendor",
      "start_date" => "2025-01-01",
      "end_date" => "2026-12-31",
      "monthly_value" => 1200.00,
      "total_value" => 28800.00,
      "auto_renews" => true,
      "renewal_term" => "annual",
      "notice_period_days" => 30,
      "contract_type" => "maintenance",
      "direction" => "outbound",
      "key_clauses" => [
        { "clause_type" => "termination", "content" => "Either party may terminate with 30 days notice" }
      ]
    }
  end

  def build_lease_extraction
    build_generic_extraction.merge(
      "contract_type" => "lease",
      "lease_details" => {
        "lease_type" => "nnn",
        "rentable_sqft" => 5000,
        "usable_sqft" => 4500,
        "load_factor" => 1.11,
        "permitted_use" => "General office",
        "security_deposit" => 25000,
        "parking_spaces" => 10,
        "parking_monthly_cost" => 150,
        "free_rent_months" => 3,
        "cam_base_amount" => 5000,
        "cam_base_year" => 2025,
        "cam_cap_percentage" => 5.0,
        "cam_cap_type" => "cumulative",
        "cam_audit_rights" => true,
        "cam_gross_up_provision" => false,
        "ti_allowance_psf" => 45.00,
        "ti_total_amount" => 225000,
        "ti_disbursement_type" => "lump_sum",
        "rent_commencement_date" => "2025-04-01"
      },
      "rent_escalations" => [
        { "effective_date" => "2026-01-01", "base_rent_monthly" => 8750.00, "escalation_type" => "fixed_percentage", "escalation_value" => 3.0 }
      ],
      "lease_options" => [
        { "option_type" => "renewal", "exercise_deadline" => "2030-06-01", "term_length_months" => 60 }
      ],
      "lease_milestones" => [
        { "milestone_type" => "custom", "due_date" => "2025-01-01", "description" => "Lease begins" }
      ]
    )
  end
end
