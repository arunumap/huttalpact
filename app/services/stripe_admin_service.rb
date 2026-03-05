class StripeAdminService
  PRODUCT_CONFIGS = {
    "starter" => {
      name: "PactBadger Starter",
      description: "Smart contract tracking for growing businesses. Up to 100 contracts, 50 AI extractions/month, 5 team members."
    },
    "pro" => {
      name: "PactBadger Pro",
      description: "Unlimited contract tracking for teams of any size. Unlimited contracts, AI extractions, and team members."
    }
  }.freeze

  PRICE_CONFIGS = [
    { lookup_key: "starter_monthly", plan: "starter", amount: 4900,   interval: "month" },
    { lookup_key: "starter_annual",  plan: "starter", amount: 49200,  interval: "year" },
    { lookup_key: "pro_monthly",     plan: "pro",     amount: 14900,  interval: "month" },
    { lookup_key: "pro_annual",      plan: "pro",     amount: 149000, interval: "year" }
  ].freeze

  # Read-only check of current Stripe products/prices status
  def self.verify_products_and_prices
    configs = lookup_key_configs
    lookup_keys = configs.map { |config| config[:lookup_key] }.uniq
    return { complete: true, prices: [], missing_keys: [], lookup_keys: [] } if lookup_keys.empty?

    existing = Stripe::Price.list(lookup_keys: lookup_keys, active: true)
    existing_keys = existing.data.map(&:lookup_key).compact

    prices = existing.data.map do |price|
      {
        lookup_key: price.lookup_key,
        price_id: price.id,
        amount: price.unit_amount,
        interval: price.recurring&.interval,
        product_name: price.product.is_a?(String) ? price.product : price.product&.name
      }
    end

    missing_keys = lookup_keys - existing_keys

    {
      complete: missing_keys.empty?,
      prices: prices,
      missing_keys: missing_keys,
      lookup_keys: lookup_keys
    }
  rescue Stripe::StripeError => e
    { complete: false, prices: [], missing_keys: [], lookup_keys: [], error: true, message: e.message }
  end

  # Creates missing Stripe products and prices (idempotent)
  def self.setup_products_and_prices!
    configs = lookup_key_configs
    lookup_keys = configs.map { |config| config[:lookup_key] }.uniq
    return { success: true, message: "No active paid tier prices configured.", created: [], skipped: [] } if lookup_keys.empty?

    existing = Stripe::Price.list(lookup_keys: lookup_keys, active: true)
    existing_keys = existing.data.map(&:lookup_key).compact
    existing_by_lookup = existing.data.index_by(&:lookup_key)

    created = []
    skipped = []
    products_cache = {}

    updated = []

    configs.each do |config|
      if existing_keys.include?(config[:lookup_key])
        existing_price = existing_by_lookup[config[:lookup_key]]

        if existing_price && existing_price.unit_amount != config[:amount]
          # Amount changed — create a new price and transfer the lookup key
          product = products_cache[config[:plan]] ||= find_or_create_product(config[:plan], tier: config[:tier])

          price = Stripe::Price.create(
            product: product.id,
            unit_amount: config[:amount],
            currency: "usd",
            recurring: { interval: config[:interval] },
            lookup_key: config[:lookup_key],
            transfer_lookup_key: true
          )

          update_tier_stripe_ids(config[:tier], price, config[:interval], product.id) if config[:tier]
          updated << config[:lookup_key]
        else
          skipped << config[:lookup_key]
          update_tier_stripe_ids(config[:tier], existing_price, config[:interval]) if config[:tier] && existing_price
        end
        next
      end

      product = products_cache[config[:plan]] ||= find_or_create_product(config[:plan], tier: config[:tier])

      price = Stripe::Price.create(
        product: product.id,
        unit_amount: config[:amount],
        currency: "usd",
        recurring: { interval: config[:interval] },
        lookup_key: config[:lookup_key],
        transfer_lookup_key: true
      )

      update_tier_stripe_ids(config[:tier], price, config[:interval], product.id)
      created << config[:lookup_key]
    end

    { success: true, message: "Setup complete", created: created, skipped: skipped, updated: updated }
  rescue Stripe::StripeError => e
    { success: false, message: e.message, created: created || [], skipped: skipped || [], updated: updated || [] }
  end

  # Creates a Stripe Billing Portal Configuration
  def self.configure_billing_portal!
    configuration = Stripe::BillingPortal::Configuration.create({
      features: {
        payment_method_update: { enabled: true },
        invoice_history: { enabled: true },
        subscription_cancel: { enabled: false },
        subscription_update: { enabled: false },
        subscription_pause: { enabled: false }
      },
      business_profile: {
        headline: "PactBadger — Manage your payment methods and invoices"
      }
    })

    { success: true, configuration_id: configuration.id, message: "Portal configuration created" }
  rescue Stripe::StripeError => e
    { success: false, message: e.message }
  end

  # Syncs all organizations with active Pay subscriptions against Stripe
  def self.sync_all_organizations!
    orgs = Organization.joins(pay_customers: :subscriptions)
                       .where(pay_subscriptions: { status: "active" })
                       .distinct

    synced = 0
    failed = 0
    errors = []
    details = []

    orgs.find_each do |org|
      result = sync_organization!(org)
      if result[:success]
        synced += 1
        details << {
          org_id: org.id,
          org_name: org.name,
          old_plan: result[:old_plan],
          new_plan: result[:new_plan],
          changed: result[:changed]
        }
      else
        failed += 1
        errors << { org_id: org.id, org_name: org.name, message: result[:message] }
      end
    end

    { success: true, synced: synced, failed: failed, errors: errors, details: details }
  rescue => e
    { success: false, message: e.message, synced: synced || 0, failed: failed || 0, errors: errors || [], details: details || [] }
  end

  # Syncs a single organization's plan from its Stripe subscription
  def self.sync_organization!(organization)
    old_plan = organization.plan
    organization.sync_plan_from_subscription!
    organization.reload
    new_plan = organization.plan

    { success: true, organization_id: organization.id, old_plan: old_plan, new_plan: new_plan, changed: old_plan != new_plan }
  rescue => e
    { success: false, organization_id: organization.id, message: e.message }
  end

  # Syncs Stripe product + prices for a single tier
  def self.sync_plan_tier!(plan_tier)
    return { success: false, message: "Free tier does not require Stripe prices." } if plan_tier.free?

    configs = tier_lookup_key_configs(plan_tier)
    return { success: false, message: "Tier is missing Stripe lookup keys or prices." } if configs.empty?

    lookup_keys = configs.map { |config| config[:lookup_key] }
    existing = Stripe::Price.list(lookup_keys: lookup_keys, active: true)
    existing_by_lookup = existing.data.index_by(&:lookup_key)

    product = nil
    created = []
    skipped = []

    updated = []

    configs.each do |config|
      existing_price = existing_by_lookup[config[:lookup_key]]
      if existing_price
        if existing_price.unit_amount == config[:amount]
          skipped << config[:lookup_key]
          update_tier_stripe_ids(plan_tier, existing_price, config[:interval])
          next
        else
          # Amount changed — create a new price and transfer the lookup key
          # (Stripe prices are immutable; transfer_lookup_key reassigns the key)
          product ||= find_or_create_product(plan_tier.slug, tier: plan_tier)
          price = Stripe::Price.create(
            product: product.id,
            unit_amount: config[:amount],
            currency: "usd",
            recurring: { interval: config[:interval] },
            lookup_key: config[:lookup_key],
            transfer_lookup_key: true
          )

          update_tier_stripe_ids(plan_tier, price, config[:interval], product.id)
          updated << config[:lookup_key]
          next
        end
      end

      product ||= find_or_create_product(plan_tier.slug, tier: plan_tier)
      price = Stripe::Price.create(
        product: product.id,
        unit_amount: config[:amount],
        currency: "usd",
        recurring: { interval: config[:interval] },
        lookup_key: config[:lookup_key],
        transfer_lookup_key: true
      )

      update_tier_stripe_ids(plan_tier, price, config[:interval], product.id)
      created << config[:lookup_key]
    end

    { success: true, message: "Tier sync complete", created: created, skipped: skipped, updated: updated }
  rescue Stripe::StripeError => e
    { success: false, message: e.message, created: created || [], skipped: skipped || [], updated: updated || [] }
  end

  # Finds or creates a Stripe product
  def self.find_or_create_product(plan_key, tier: nil)
    if tier
      if tier.stripe_product_id.present?
        begin
          return Stripe::Product.retrieve(tier.stripe_product_id)
        rescue Stripe::InvalidRequestError
        end
      end

      product_name = "PactBadger #{tier.name}"
      description = tier.description.presence || "Plan tier #{tier.name}"
    else
      config = PRODUCT_CONFIGS[plan_key]
      product_name = config[:name]
      description = config[:description]
    end

    products = Stripe::Product.list(limit: 100, active: true)
    existing = products.data.find { |p| p.name == product_name }

    product = existing || Stripe::Product.create(name: product_name, description: description)

    if tier && tier.stripe_product_id != product.id
      tier.update_column(:stripe_product_id, product.id)
    end

    product
  end

  def self.lookup_key_configs
    if PlanCatalogService.plan_tiers_available?
      configs = PlanTier.active.ordered.flat_map { |tier| tier_lookup_key_configs(tier) }
      return configs if configs.any?
    end

    PRICE_CONFIGS.map { |config| config.merge(tier: nil) }
  end

  def self.tier_lookup_key_configs(tier)
    return [] unless tier.active?

    configs = []

    if tier.monthly_lookup_key.present? && tier.monthly_price_cents.to_i.positive?
      configs << {
        lookup_key: tier.monthly_lookup_key,
        plan: tier.slug,
        amount: tier.monthly_price_cents,
        interval: "month",
        tier: tier
      }
    end

    if tier.annual_lookup_key.present? && tier.annual_price_cents.to_i.positive?
      configs << {
        lookup_key: tier.annual_lookup_key,
        plan: tier.slug,
        amount: tier.annual_price_cents,
        interval: "year",
        tier: tier
      }
    end

    configs
  end

  def self.update_tier_stripe_ids(tier, price, interval, product_id = nil)
    return unless tier&.persisted?

    attrs = {
      stripe_product_id: product_id || stripe_product_id_for(price)
    }

    if interval == "month"
      attrs[:stripe_monthly_price_id] = price.id
    elsif interval == "year"
      attrs[:stripe_annual_price_id] = price.id
    end

    tier.update_columns(attrs.compact)
  end

  def self.stripe_product_id_for(price)
    product = price.product
    product.is_a?(String) ? product : product&.id
  end

  private_class_method :find_or_create_product,
                       :lookup_key_configs,
                       :tier_lookup_key_configs,
                       :update_tier_stripe_ids,
                       :stripe_product_id_for
end
