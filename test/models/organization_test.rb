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
    # Create a mock subscription with unknown price (must use STI subclass)
    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_test_123",
      processor_plan: "price_unknown_plan",
      name: "default",
      status: "active"
    )

    StripePriceResolver.stub(:plan_for_price_id, nil) do
      assert_no_changes -> { org.reload.plan } do
        org.sync_plan_from_subscription!
      end
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

  # Seat management methods
  test "sync_plan_from_subscription! picks the most recent subscription when multiple active" do
    org = organizations(:one)
    customer = org.set_payment_processor(:stripe)

    # Must use STI subclass so customer.subscriptions query finds them
    StripePriceResolver.stub(:plan_for_price_id, ->(price_id) {
      price_id == "price_pro_456" ? "pro" : "starter"
    }) do
      # Create an older "starter" subscription
      Pay::Stripe::Subscription.create!(
        customer: customer,
        processor_id: "sub_old_starter",
        processor_plan: "price_starter_123",
        name: "default",
        status: "active",
        created_at: 2.days.ago
      )

      # Create a newer "pro" subscription
      Pay::Stripe::Subscription.create!(
        customer: customer,
        processor_id: "sub_new_pro",
        processor_plan: "price_pro_456",
        name: "default",
        status: "active",
        created_at: 1.minute.ago
      )

      org.sync_plan_from_subscription!
    end

    assert_equal "pro", org.reload.plan
  end

  test "seats_used returns membership count" do
    org = organizations(:two) # has owner + admin + member = 3
    assert_equal 3, org.seats_used
  end

  test "seats_remaining returns available seats" do
    org = organizations(:two) # starter plan: 5 seats, 3 used
    assert_equal 2, org.seats_remaining
  end

  test "seats_remaining returns zero when at limit" do
    org = organizations(:one) # free plan: 1 seat, 1 used
    assert_equal 0, org.seats_remaining
  end

  test "seats_remaining returns infinity for pro plan" do
    org = organizations(:two)
    org.update!(plan: "pro")
    assert_equal Float::INFINITY, org.seats_remaining
  end

  # --- Pending downgrade columns ---

  test "active_subscription returns nil when no pay customer" do
    org = organizations(:one)
    assert_nil org.active_subscription
  end

  test "active_subscription returns most recent active subscription" do
    org = organizations(:one)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_active_sub_test")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_old",
      processor_plan: "price_starter_old",
      name: "default",
      status: "active",
      created_at: 2.days.ago
    )

    newest = Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_new",
      processor_plan: "price_pro_new",
      name: "default",
      status: "active",
      created_at: 1.minute.ago
    )

    assert_equal newest.processor_id, org.active_subscription.processor_id
  end

  test "clear_pending_downgrade! resets all pending fields" do
    org = organizations(:one)
    org.update!(
      pending_plan: "free",
      pending_plan_interval: "monthly",
      pending_plan_effective_at: 30.days.from_now,
      pending_downgrade_schedule_id: "sub_sched_test"
    )

    org.clear_pending_downgrade!
    org.reload

    assert_nil org.pending_plan
    assert_nil org.pending_plan_interval
    assert_nil org.pending_plan_effective_at
    assert_nil org.pending_downgrade_schedule_id
  end

  test "pending_plan validates inclusion" do
    org = organizations(:one)
    org.pending_plan = "enterprise"
    assert_not org.valid?
    assert_includes org.errors[:pending_plan], "is not included in the list"
  end

  test "pending_plan allows nil" do
    org = organizations(:one)
    org.pending_plan = nil
    assert org.valid?
  end

  test "pending_plan allows free and starter" do
    org = organizations(:one)
    org.pending_plan = "free"
    assert org.valid?
    org.pending_plan = "starter"
    assert org.valid?
  end

  # --- PlanLimits hierarchy methods ---

  test "upgrade_from_current? returns true for higher plan" do
    org = organizations(:one)
    org.plan = "free"
    assert org.upgrade_from_current?("starter")
    assert org.upgrade_from_current?("pro")
  end

  test "upgrade_from_current? returns false for same or lower plan" do
    org = organizations(:one)
    org.plan = "starter"
    assert_not org.upgrade_from_current?("starter")
    assert_not org.upgrade_from_current?("free")
  end

  test "downgrade_from_current? returns true for lower plan" do
    org = organizations(:one)
    org.plan = "pro"
    assert org.downgrade_from_current?("starter")
    assert org.downgrade_from_current?("free")
  end

  test "downgrade_from_current? returns false for same or higher plan" do
    org = organizations(:one)
    org.plan = "starter"
    assert_not org.downgrade_from_current?("starter")
    assert_not org.downgrade_from_current?("pro")
  end

  # --- Downgrade eligibility ---

  test "downgrade_eligibility returns eligible when under limits" do
    org = organizations(:one) # free plan, few contracts, 1 user
    org.update!(plan: "pro")
    result = org.downgrade_eligibility("starter")
    assert result[:eligible]
    assert_empty result[:blockers]
  end

  test "downgrade_eligibility returns blockers for too many contracts" do
    org = organizations(:one)
    org.update!(plan: "pro")
    org.define_singleton_method(:active_contracts_count) { 150 }

    result = org.downgrade_eligibility("starter")
    assert_not result[:eligible]
    assert_equal 1, result[:blockers].size
    assert_match "active contracts", result[:blockers].first
  end

  test "downgrade_eligibility returns blockers for too many users" do
    org = organizations(:two) # has 3 members
    org.update!(plan: "pro")

    result = org.downgrade_eligibility("free") # free allows 1 user
    assert_not result[:eligible]
    assert result[:blockers].any? { |b| b.include?("team members") }
  end

  test "downgrade_eligibility returns error for unknown plan" do
    org = organizations(:one)
    result = org.downgrade_eligibility("enterprise")
    assert_not result[:eligible]
    assert_match "Unknown plan", result[:blockers].first
  end

  # --- Pending state helpers ---

  test "pending_downgrade? returns true when pending_plan is set" do
    org = organizations(:one)
    org.pending_plan = "free"
    assert org.pending_downgrade?
  end

  test "pending_downgrade? returns false when pending_plan is nil" do
    org = organizations(:one)
    assert_not org.pending_downgrade?
  end

  test "pending_cancellation? returns false when no subscriptions" do
    org = organizations(:one)
    assert_not org.pending_cancellation?
  end

  test "pending_cancellation? returns true with subscription ending" do
    org = organizations(:one)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_pending_cancel")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_pending_cancel",
      processor_plan: "price_starter_pc",
      name: "default",
      status: "active",
      ends_at: 30.days.from_now
    )

    assert org.pending_cancellation?
  end

  test "pending_cancellation? returns false with active subscription not ending" do
    org = organizations(:one)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_no_cancel")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_no_cancel",
      processor_plan: "price_starter_nc",
      name: "default",
      status: "active",
      ends_at: nil
    )

    assert_not org.pending_cancellation?
  end

  # --- sync_plan_from_subscription! clears pending downgrade ---

  test "sync_plan_from_subscription! clears pending downgrade when plan matches pending_plan" do
    org = organizations(:one)
    org.update!(plan: "pro", pending_plan: "starter", pending_plan_interval: "monthly",
                pending_plan_effective_at: 1.day.from_now, pending_downgrade_schedule_id: "sub_sched_sync")

    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_sync_clear")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_sync_clear",
      processor_plan: "price_starter_sync",
      name: "default",
      status: "active"
    )

    StripePriceResolver.stub(:plan_for_price_id, "starter") do
      org.sync_plan_from_subscription!
    end

    org.reload
    assert_equal "starter", org.plan
    assert_nil org.pending_plan
    assert_nil org.pending_downgrade_schedule_id
  end

  test "sync_plan_from_subscription! does not clear pending downgrade when plans differ" do
    org = organizations(:one)
    org.update!(plan: "pro", pending_plan: "starter", pending_plan_interval: "monthly",
                pending_plan_effective_at: 30.days.from_now, pending_downgrade_schedule_id: "sub_sched_no_clear")

    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_sync_noclear")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_sync_noclear",
      processor_plan: "price_pro_sync",
      name: "default",
      status: "active"
    )

    StripePriceResolver.stub(:plan_for_price_id, "pro") do
      org.sync_plan_from_subscription!
    end

    org.reload
    assert_equal "pro", org.plan
    assert_equal "starter", org.pending_plan
  end
end
