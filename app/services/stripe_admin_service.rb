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
    lookup_keys = PlanLimits::LOOKUP_KEYS.keys
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
      missing_keys: missing_keys
    }
  rescue Stripe::StripeError => e
    { complete: false, prices: [], missing_keys: [], error: true, message: e.message }
  end

  # Creates missing Stripe products and prices (idempotent)
  def self.setup_products_and_prices!
    lookup_keys = PlanLimits::LOOKUP_KEYS.keys
    existing = Stripe::Price.list(lookup_keys: lookup_keys, active: true)
    existing_keys = existing.data.map(&:lookup_key).compact

    created = []
    skipped = []
    products_cache = {}

    PRICE_CONFIGS.each do |config|
      if existing_keys.include?(config[:lookup_key])
        skipped << config[:lookup_key]
        next
      end

      product = products_cache[config[:plan]] ||= find_or_create_product(config[:plan])

      Stripe::Price.create(
        product: product.id,
        unit_amount: config[:amount],
        currency: "usd",
        recurring: { interval: config[:interval] },
        lookup_key: config[:lookup_key],
        transfer_lookup_key: true
      )

      created << config[:lookup_key]
    end

    { success: true, message: "Setup complete", created: created, skipped: skipped }
  rescue Stripe::StripeError => e
    { success: false, message: e.message, created: created || [], skipped: skipped || [] }
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

  # Finds or creates a Stripe product
  def self.find_or_create_product(plan_key)
    config = PRODUCT_CONFIGS[plan_key]
    products = Stripe::Product.list(limit: 100, active: true)
    existing = products.data.find { |p| p.name == config[:name] }

    return existing if existing

    Stripe::Product.create(name: config[:name], description: config[:description])
  end

  private_class_method :find_or_create_product
end
