require "test_helper"
require "ostruct"

class StripeAdminServiceTest < ActiveSupport::TestCase
  # ── verify_products_and_prices ──

  test "verify_products_and_prices returns complete when all 4 lookup key prices exist" do
    mock_prices = PlanCatalogService.lookup_keys.keys.map.with_index do |key, i|
      OpenStruct.new(
        lookup_key: key,
        id: "price_#{i}",
        unit_amount: [ 4900, 49200, 14900, 149000 ][i],
        recurring: OpenStruct.new(interval: i.even? ? "month" : "year"),
        product: "prod_#{i}"
      )
    end

    mock_list = OpenStruct.new(data: mock_prices)

    Stripe::Price.stub :list, mock_list do
      result = StripeAdminService.verify_products_and_prices

      assert result[:complete]
      assert_empty result[:missing_keys]
      assert_equal 4, result[:prices].size
    end
  end

  test "verify_products_and_prices returns incomplete with missing keys when some prices are missing" do
    mock_prices = [
      OpenStruct.new(
        lookup_key: "starter_monthly",
        id: "price_0",
        unit_amount: 4900,
        recurring: OpenStruct.new(interval: "month"),
        product: "prod_0"
      )
    ]
    mock_list = OpenStruct.new(data: mock_prices)

    Stripe::Price.stub :list, mock_list do
      result = StripeAdminService.verify_products_and_prices

      refute result[:complete]
      assert_includes result[:missing_keys], "starter_annual"
      assert_includes result[:missing_keys], "pro_monthly"
      assert_includes result[:missing_keys], "pro_annual"
      assert_equal 1, result[:prices].size
    end
  end

  test "verify_products_and_prices returns error result when Stripe API fails" do
    Stripe::Price.stub :list, ->(_) { raise Stripe::StripeError, "API down" } do
      result = StripeAdminService.verify_products_and_prices

      refute result[:complete]
      assert result[:error]
      assert_equal "API down", result[:message]
    end
  end

  # ── setup_products_and_prices! ──

  test "setup_products_and_prices creates missing products and prices" do
    # All prices missing
    mock_list = OpenStruct.new(data: [])
    mock_product = OpenStruct.new(id: "prod_new", name: "PactBadger Starter")
    mock_products_list = OpenStruct.new(data: [])
    mock_price = OpenStruct.new(id: "price_new")

    Stripe::Price.stub :list, mock_list do
      Stripe::Product.stub :list, mock_products_list do
        Stripe::Product.stub :create, mock_product do
          Stripe::Price.stub :create, mock_price do
            result = StripeAdminService.setup_products_and_prices!

            assert result[:success]
            assert_equal 4, result[:created].size
            assert_empty result[:skipped]
          end
        end
      end
    end
  end

  test "setup_products_and_prices skips existing prices (idempotent)" do
    # All prices already exist
    mock_prices = PlanCatalogService.lookup_keys.keys.map do |key|
      OpenStruct.new(lookup_key: key, id: "price_existing")
    end
    mock_list = OpenStruct.new(data: mock_prices)

    Stripe::Price.stub :list, mock_list do
      result = StripeAdminService.setup_products_and_prices!

      assert result[:success]
      assert_empty result[:created]
      assert_equal 4, result[:skipped].size
    end
  end

  test "setup_products_and_prices returns error on Stripe API failure" do
    Stripe::Price.stub :list, ->(_) { raise Stripe::StripeError, "Connection failed" } do
      result = StripeAdminService.setup_products_and_prices!

      refute result[:success]
      assert_equal "Connection failed", result[:message]
    end
  end

  # ── configure_billing_portal! ──

  test "configure_billing_portal creates portal configuration and returns configuration ID" do
    mock_config = OpenStruct.new(id: "bpc_test123")

    Stripe::BillingPortal::Configuration.stub :create, mock_config do
      result = StripeAdminService.configure_billing_portal!

      assert result[:success]
      assert_equal "bpc_test123", result[:configuration_id]
    end
  end

  test "configure_billing_portal returns error on Stripe API failure" do
    Stripe::BillingPortal::Configuration.stub :create, ->(_) { raise Stripe::StripeError, "Forbidden" } do
      result = StripeAdminService.configure_billing_portal!

      refute result[:success]
      assert_equal "Forbidden", result[:message]
    end
  end

  # ── sync_organization! ──

  test "sync_organization returns changed true when plan changes" do
    org = organizations(:one)
    org.update!(plan: "free")

    # Stub sync_plan_from_subscription! to change plan to starter
    org.stub :sync_plan_from_subscription!, -> { org.update!(plan: "starter") } do
      result = StripeAdminService.sync_organization!(org)

      assert result[:success]
      assert_equal "free", result[:old_plan]
      assert_equal "starter", result[:new_plan]
      assert result[:changed]
    end
  end

  test "sync_organization returns changed false when already in sync" do
    org = organizations(:one)
    org.update!(plan: "starter")

    # Stub as no-op (plan doesn't change)
    org.stub :sync_plan_from_subscription!, -> { } do
      result = StripeAdminService.sync_organization!(org)

      assert result[:success]
      assert_equal "starter", result[:old_plan]
      assert_equal "starter", result[:new_plan]
      refute result[:changed]
    end
  end

  test "sync_organization handles errors gracefully" do
    org = organizations(:one)

    org.stub :sync_plan_from_subscription!, -> { raise StandardError, "Stripe unreachable" } do
      result = StripeAdminService.sync_organization!(org)

      refute result[:success]
      assert_equal "Stripe unreachable", result[:message]
    end
  end

  # ── sync_all_organizations! ──

  test "sync_all_organizations returns empty result when no orgs have subscriptions" do
    # With no Pay subscriptions, the query returns empty
    result = StripeAdminService.sync_all_organizations!

    assert result[:success]
    assert_equal 0, result[:synced]
    assert_equal 0, result[:failed]
    assert_empty result[:details]
  end
end
