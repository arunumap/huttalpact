class StripePriceResolver
  CACHE_TTL = 1.hour

  # Resolve a lookup key to the current Stripe Price ID.
  # Used at checkout time to get the active price for a plan variant.
  #
  # @param lookup_key [String] e.g. "starter_monthly"
  # @return [String] Stripe price ID (e.g. "price_1Abc...")
  # @raise [StripePriceResolver::PriceNotFound] if no price exists with that lookup key
  def self.resolve_checkout_price(lookup_key)
    prices = Stripe::Price.list(lookup_keys: [ lookup_key ], active: true)
    price = prices.data.first

    raise PriceNotFound, "No active Stripe price found for lookup key '#{lookup_key}'" unless price

    price.id
  end

  # Given a Stripe Price ID (from a subscription's processor_plan),
  # resolve it to a plan name ("starter" or "pro") by retrieving
  # the price from Stripe and reading its lookup_key.
  #
  # Results are cached to avoid repeated API calls for the same price.
  #
  # @param price_id [String] Stripe price ID (e.g. "price_1Abc...")
  # @return [String, nil] plan name ("starter", "pro") or nil if unrecognized
  def self.plan_for_price_id(price_id)
    return nil if price_id.blank?

    cache_key = "stripe_price_plan:#{price_id}"
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    price = Stripe::Price.retrieve(price_id)
    plan_name = PlanLimits::LOOKUP_KEYS[price.lookup_key]

    # Only cache non-nil results so unrecognized prices can be retried
    # after lookup_key is configured in Stripe.
    if plan_name
      Rails.cache.write(cache_key, plan_name, expires_in: CACHE_TTL)
    else
      Rails.logger.warn("Unmapped Stripe lookup_key '#{price.lookup_key}' for price '#{price_id}'")
    end

    plan_name
  rescue Stripe::StripeError => e
    Rails.logger.warn("Stripe price retrieval failed for '#{price_id}': #{e.message}")
    nil
  end

  class PriceNotFound < StandardError; end
end
