require "test_helper"

class PlanLimitsTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
  end

  # Contract limits
  test "free plan has 10 contract limit" do
    @org.plan = "free"
    assert_equal 10, @org.plan_contract_limit
  end

  test "starter plan has 100 contract limit" do
    @org.plan = "starter"
    assert_equal 100, @org.plan_contract_limit
  end

  test "pro plan has unlimited contract limit" do
    @org.plan = "pro"
    assert_equal Float::INFINITY, @org.plan_contract_limit
  end

  # Extraction limits
  test "free plan has 5 extraction limit" do
    @org.plan = "free"
    assert_equal 5, @org.plan_extraction_limit
  end

  test "starter plan has 50 extraction limit" do
    @org.plan = "starter"
    assert_equal 50, @org.plan_extraction_limit
  end

  test "pro plan has unlimited extraction limit" do
    @org.plan = "pro"
    assert_equal Float::INFINITY, @org.plan_extraction_limit
  end

  # User limits
  test "free plan has 1 user limit" do
    @org.plan = "free"
    assert_equal 1, @org.plan_user_limit
  end

  test "starter plan has 5 user limit" do
    @org.plan = "starter"
    assert_equal 5, @org.plan_user_limit
  end

  test "pro plan has unlimited user limit" do
    @org.plan = "pro"
    assert_equal Float::INFINITY, @org.plan_user_limit
  end

  # at_contract_limit?
  test "at_contract_limit? returns false when under limit" do
    @org.plan = "free"
    @org.stub(:active_contracts_count, 5) do
      assert_not @org.at_contract_limit?
    end
  end

  test "at_contract_limit? returns true when at limit" do
    @org.plan = "free"
    @org.stub(:active_contracts_count, 10) do
      assert @org.at_contract_limit?
    end
  end

  test "at_contract_limit? returns true when over limit" do
    @org.plan = "free"
    @org.stub(:active_contracts_count, 15) do
      assert @org.at_contract_limit?
    end
  end

  test "at_contract_limit? returns false for pro plan" do
    @org.plan = "pro"
    @org.stub(:active_contracts_count, 9999) do
      assert_not @org.at_contract_limit?
    end
  end

  # at_extraction_limit?
  test "at_extraction_limit? returns false when under limit" do
    @org.plan = "free"
    @org.update!(ai_extractions_count: 3, ai_extractions_reset_at: Time.current)
    assert_not @org.at_extraction_limit?
  end

  test "at_extraction_limit? returns true when at limit" do
    @org.plan = "free"
    @org.update!(ai_extractions_count: 5, ai_extractions_reset_at: Time.current)
    assert @org.at_extraction_limit?
  end

  # at_user_limit?
  test "at_user_limit? returns true for free plan with 1 member" do
    @org.plan = "free"
    assert @org.at_user_limit? # already has 1 membership (owner)
  end

  # increment_extraction_count!
  test "increment_extraction_count! increases count" do
    @org.update!(ai_extractions_count: 2, ai_extractions_reset_at: Time.current)
    @org.increment_extraction_count!
    assert_equal 3, @org.reload.ai_extractions_count
  end

  # reset_monthly_extractions!
  test "reset_monthly_extractions! resets count to zero" do
    @org.update!(ai_extractions_count: 5, ai_extractions_reset_at: 2.months.ago)
    @org.reset_monthly_extractions!
    assert_equal 0, @org.reload.ai_extractions_count
    assert_not_nil @org.ai_extractions_reset_at
  end

  # Auto-reset: at_extraction_limit? no longer auto-resets (side-effect removed)
  # Reset must be called explicitly via reset_monthly_extractions_if_needed!
  test "reset_monthly_extractions_if_needed! resets when new month" do
    @org.plan = "free"
    @org.update!(ai_extractions_count: 5, ai_extractions_reset_at: 2.months.ago)
    @org.reset_monthly_extractions_if_needed!
    assert_not @org.at_extraction_limit?
    assert_equal 0, @org.reload.ai_extractions_count
  end

  # contracts_remaining
  test "contracts_remaining returns correct count" do
    @org.plan = "free"
    @org.stub(:active_contracts_count, 7) do
      assert_equal 3, @org.contracts_remaining
    end
  end

  test "contracts_remaining returns infinity for pro" do
    @org.plan = "pro"
    assert_equal Float::INFINITY, @org.contracts_remaining
  end

  # near_contract_limit?
  test "near_contract_limit? returns true within threshold" do
    @org.plan = "free"
    @org.stub(:active_contracts_count, 9) do
      assert @org.near_contract_limit?
    end
  end

  test "near_contract_limit? returns false when well under" do
    @org.plan = "free"
    @org.stub(:active_contracts_count, 5) do
      assert_not @org.near_contract_limit?
    end
  end

  test "near_contract_limit? returns false for pro" do
    @org.plan = "pro"
    @org.stub(:active_contracts_count, 9999) do
      assert_not @org.near_contract_limit?
    end
  end

  # Plan helpers
  test "free_plan? returns true for free" do
    @org.plan = "free"
    assert @org.free_plan?
  end

  test "paid_plan? returns true for starter" do
    @org.plan = "starter"
    assert @org.paid_plan?
  end

  test "paid_plan? returns true for pro" do
    @org.plan = "pro"
    assert @org.paid_plan?
  end

  test "paid_plan? returns false for free" do
    @org.plan = "free"
    assert_not @org.paid_plan?
  end

  test "plan_display_name returns titleized plan" do
    @org.plan = "starter"
    assert_equal "Starter", @org.plan_display_name
  end

  test "active_contracts_count excludes archived contracts" do
    # org one has fixtures contracts, archive one
    active_before = @org.active_contracts_count
    contract = @org.contracts.not_archived.first
    contract.update!(status: "archived")
    assert_equal active_before - 1, @org.active_contracts_count
  end

  test "at_contract_limit? excludes archived contracts" do
    @org.plan = "free"
    # Archive all contracts, then create exactly 10 non-archived
    @org.contracts.update_all(status: "archived")
    assert_not @org.at_contract_limit?
  end

  test "increment_extraction_count! returns true when under limit" do
    @org.plan = "free"
    @org.update!(ai_extractions_count: 3, ai_extractions_reset_at: Time.current)
    assert @org.increment_extraction_count!
    assert_equal 4, @org.reload.ai_extractions_count
  end

  test "increment_extraction_count! returns false when at limit" do
    @org.plan = "free"
    @org.update!(ai_extractions_count: 5, ai_extractions_reset_at: Time.current)
    assert_not @org.increment_extraction_count!
    assert_equal 5, @org.reload.ai_extractions_count
  end

  test "increment_extraction_count! always succeeds for pro plan" do
    @org.plan = "pro"
    @org.update!(ai_extractions_count: 9999, ai_extractions_reset_at: Time.current)
    assert @org.increment_extraction_count!
    assert_equal 10000, @org.reload.ai_extractions_count
  end

  test "increment_extraction_count! resets if new month before incrementing" do
    @org.plan = "free"
    @org.update!(ai_extractions_count: 5, ai_extractions_reset_at: 2.months.ago)
    assert @org.increment_extraction_count!
    # Reset to 0, then incremented to 1
    assert_equal 1, @org.reload.ai_extractions_count
  end

  test "reset_monthly_extractions_if_needed! is a no-op when already reset this month" do
    @org.update!(ai_extractions_count: 3, ai_extractions_reset_at: Time.current)
    @org.reset_monthly_extractions_if_needed!
    assert_equal 3, @org.reload.ai_extractions_count
  end

  # near_extraction_limit?
  test "near_extraction_limit? returns true when within threshold" do
    @org.plan = "free" # 5 limit
    @org.update!(ai_extractions_count: 4, ai_extractions_reset_at: Time.current)
    assert @org.near_extraction_limit?
  end

  test "near_extraction_limit? returns false when well under limit" do
    @org.plan = "free" # 5 limit
    @org.update!(ai_extractions_count: 1, ai_extractions_reset_at: Time.current)
    assert_not @org.near_extraction_limit?
  end

  test "near_extraction_limit? returns false for pro plan" do
    @org.plan = "pro"
    @org.update!(ai_extractions_count: 9999, ai_extractions_reset_at: Time.current)
    assert_not @org.near_extraction_limit?
  end

  test "near_extraction_limit? accepts custom threshold" do
    @org.plan = "free" # 5 limit
    @org.update!(ai_extractions_count: 2, ai_extractions_reset_at: Time.current)
    assert_not @org.near_extraction_limit?(2) # 2 < 5 - 2 = 3
    assert @org.near_extraction_limit?(3) # 2 >= 5 - 3 = 2
  end
end
