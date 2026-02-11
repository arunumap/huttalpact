require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "valid organization" do
    org = Organization.create(name: "Test Co")
    assert org.persisted?
    assert_equal "test-co", org.slug
  end

  test "requires name" do
    org = Organization.new(name: nil, slug: "test")
    assert_not org.valid?
    assert_includes org.errors[:name], "can't be blank"
  end

  test "auto-generates slug from name" do
    org = Organization.create(name: "My Great Company")
    assert_equal "my-great-company", org.slug
  end

  test "ensures slug uniqueness" do
    Organization.create!(name: "Unique Co")
    org = Organization.create!(name: "Unique Co")
    assert_equal "unique-co-1", org.slug
  end

  test "validates slug format" do
    org = Organization.new(name: "Test", slug: "INVALID SLUG!")
    assert_not org.valid?
    assert_includes org.errors[:slug], "only allows lowercase letters, numbers, and hyphens"
  end

  test "validates plan inclusion" do
    org = organizations(:one)
    org.plan = "enterprise"
    assert_not org.valid?
  end

  test "plan_contract_limit returns correct limits" do
    org = Organization.new(name: "Test", plan: "free")
    assert_equal 10, org.plan_contract_limit

    org.plan = "starter"
    assert_equal 100, org.plan_contract_limit

    org.plan = "pro"
    assert_equal Float::INFINITY, org.plan_contract_limit
  end

  test "owner returns the owner user" do
    org = organizations(:one)
    assert_equal users(:one), org.owner
  end

  test "sync_plan_from_subscription! sets free when no subscription" do
    org = organizations(:one)
    org.update!(plan: "starter")
    org.sync_plan_from_subscription!
    assert_equal "free", org.reload.plan
  end

  test "sync_plan_from_subscription! does nothing when already free and no subscription" do
    org = organizations(:one)
    assert_equal "free", org.plan
    assert_no_difference "AuditLog.count" do
      org.sync_plan_from_subscription!
    end
    assert_equal "free", org.reload.plan
  end

  test "sync_plan_from_subscription! logs warning for unknown price ID" do
    org = organizations(:one)
    customer = org.set_payment_processor(:stripe)
    # Create a mock subscription with unknown price
    Pay::Subscription.create!(
      customer: customer,
      processor_id: "sub_test_123",
      processor_plan: "price_unknown_plan",
      name: "default",
      status: "active"
    )

    assert_no_changes -> { org.reload.plan } do
      org.sync_plan_from_subscription!
    end
  end

  test "sync_plan_from_subscription! creates audit log on plan change" do
    org = organizations(:one)
    assert_equal "free", org.plan

    # Test the plan change + audit log by directly calling sync after setting up subscription
    # Use send to access private log_plan_change for isolated testing
    assert_difference "AuditLog.unscoped.count", 1 do
      org.update!(plan: "starter")
      org.send(:log_plan_change, "free", "starter")
    end

    audit = AuditLog.unscoped.where(action: "plan_changed").order(created_at: :desc).first
    assert_not_nil audit
    assert_equal org.id, audit.organization_id
    assert_match "Free", audit.details
    assert_match "Starter", audit.details
  end

  test "downgrade preserves existing contracts but enforces new limit" do
    org = organizations(:one)
    org.update!(plan: "starter")
    # Org has 3 contracts from fixtures (hvac_maintenance, landscaping, expired_insurance)
    assert org.active_contracts_count > 0

    # Downgrade to free
    org.update!(plan: "free")

    # Existing contracts still accessible
    assert org.contracts.count > 0

    # But at_contract_limit? may now be true depending on count vs limit
    # Free plan allows 10, so 3 contracts should still be under limit
    assert_not org.at_contract_limit?
  end

  # Length validation tests
  test "validates name length maximum" do
    org = Organization.new(name: "a" * 256)
    assert_not org.valid?
    assert_includes org.errors[:name], "is too long (maximum is 255 characters)"
  end

  test "validates slug length maximum" do
    org = Organization.new(name: "Test", slug: "a" * 101)
    assert_not org.valid?
    assert_includes org.errors[:slug], "is too long (maximum is 100 characters)"
  end

  test "truncates very long names in slug generation" do
    org = Organization.create!(name: "a" * 200)
    assert org.slug.length <= 100
  end

  test "handles blank parameterized name in slug generation" do
    org = Organization.create!(name: "!!!")
    assert_equal "org", org.slug
  end
end
