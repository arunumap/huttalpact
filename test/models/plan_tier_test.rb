require "test_helper"

class PlanTierTest < ActiveSupport::TestCase
  test "free tier requires zero extraction overage cents" do
    tier = plan_tiers(:free)
    tier.extraction_overage_cents = 100

    assert_not tier.valid?
    assert_includes tier.errors[:extraction_overage_cents], "must be 0 for the free tier"
  end

  test "extraction overage cents must be non-negative" do
    tier = plan_tiers(:starter)
    tier.extraction_overage_cents = -1

    assert_not tier.valid?
    assert_includes tier.errors[:extraction_overage_cents], "must be greater than or equal to 0"
  end

  test "paid tier accepts positive extraction overage cents" do
    tier = plan_tiers(:starter)
    tier.extraction_overage_cents = 125

    assert tier.valid?
  end
end
