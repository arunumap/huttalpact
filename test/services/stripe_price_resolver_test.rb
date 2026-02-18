require "test_helper"
require "ostruct"

class StripePriceResolverTest < ActiveSupport::TestCase
  test "resolve_checkout_price returns price ID for valid lookup key" do
    fake_price = OpenStruct.new(id: "price_resolved_123", lookup_key: "starter_monthly")
    fake_response = OpenStruct.new(data: [ fake_price ])

    Stripe::Price.stub(:list, fake_response) do
      result = StripePriceResolver.resolve_checkout_price("starter_monthly")
      assert_equal "price_resolved_123", result
    end
  end

  test "resolve_checkout_price raises PriceNotFound when no price exists" do
    fake_response = OpenStruct.new(data: [])

    Stripe::Price.stub(:list, fake_response) do
      assert_raises(StripePriceResolver::PriceNotFound) do
        StripePriceResolver.resolve_checkout_price("starter_monthly")
      end
    end
  end

  test "plan_for_price_id returns plan name for known lookup key" do
    fake_price = OpenStruct.new(lookup_key: "starter_monthly")

    Rails.cache.clear
    Stripe::Price.stub(:retrieve, fake_price) do
      assert_equal "starter", StripePriceResolver.plan_for_price_id("price_abc_123")
    end
  end

  test "plan_for_price_id returns pro for pro lookup key" do
    fake_price = OpenStruct.new(lookup_key: "pro_annual")

    Rails.cache.clear
    Stripe::Price.stub(:retrieve, fake_price) do
      assert_equal "pro", StripePriceResolver.plan_for_price_id("price_pro_456")
    end
  end

  test "plan_for_price_id returns nil for unknown lookup key" do
    fake_price = OpenStruct.new(lookup_key: "unknown_key")

    Rails.cache.clear
    Stripe::Price.stub(:retrieve, fake_price) do
      assert_nil StripePriceResolver.plan_for_price_id("price_unknown")
    end
  end

  test "plan_for_price_id returns nil for blank price_id" do
    assert_nil StripePriceResolver.plan_for_price_id(nil)
    assert_nil StripePriceResolver.plan_for_price_id("")
  end

  test "plan_for_price_id returns nil on Stripe error" do
    Rails.cache.clear
    Stripe::Price.stub(:retrieve, ->(_) { raise Stripe::InvalidRequestError.new("Not found", "id") }) do
      assert_nil StripePriceResolver.plan_for_price_id("price_nonexistent")
    end
  end

  test "plan_for_price_id caches result" do
    fake_price = OpenStruct.new(lookup_key: "starter_monthly")
    call_count = 0

    memory_store = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, memory_store) do
      Stripe::Price.stub(:retrieve, ->(_) { call_count += 1; fake_price }) do
        StripePriceResolver.plan_for_price_id("price_cached_test")
        StripePriceResolver.plan_for_price_id("price_cached_test")
        assert_equal 1, call_count, "Expected Stripe API to be called only once due to caching"
      end
    end
  end
end
