namespace :stripe do
  desc "Create Stripe products and prices with lookup keys for HuttalPact plans"
  task setup: :environment do
    require "stripe"

    puts "Checking existing prices by lookup keys..."

    lookup_keys = PlanLimits::LOOKUP_KEYS.keys
    existing = Stripe::Price.list(lookup_keys: lookup_keys, active: true)
    existing_keys = existing.data.map(&:lookup_key).compact

    if existing_keys.sort == lookup_keys.sort
      puts "\n✓ All prices already exist with correct lookup keys:"
      existing.data.each do |price|
        amount = price.unit_amount / 100
        interval = price.recurring&.interval
        puts "  #{price.lookup_key}: #{price.id} ($#{amount}/#{interval})"
      end
      puts "\nNo changes needed."
      return
    end

    if existing_keys.any?
      puts "\nSome prices already exist: #{existing_keys.join(', ')}"
      puts "Missing: #{(lookup_keys - existing_keys).join(', ')}"
    end

    # Create products
    starter_product = find_or_create_product("HuttalPact Starter", "Contract tracking for growing property managers. Up to 100 contracts, 50 AI extractions/month, 5 team members.")
    pro_product = find_or_create_product("HuttalPact Pro", "Unlimited contract tracking for large portfolios & teams. Unlimited contracts, AI extractions, and team members.")

    # Create prices with lookup keys
    prices_config = [
      { lookup_key: "starter_monthly", product: starter_product.id, amount: 4900,   interval: "month" },
      { lookup_key: "starter_annual",  product: starter_product.id, amount: 49200,  interval: "year" },
      { lookup_key: "pro_monthly",     product: pro_product.id,     amount: 14900,  interval: "month" },
      { lookup_key: "pro_annual",      product: pro_product.id,     amount: 149000, interval: "year" }
    ]

    puts "\nCreating prices..."
    prices_config.each do |config|
      if existing_keys.include?(config[:lookup_key])
        puts "  ✓ #{config[:lookup_key]} already exists, skipping"
        next
      end

      price = Stripe::Price.create(
        product: config[:product],
        unit_amount: config[:amount],
        currency: "usd",
        recurring: { interval: config[:interval] },
        lookup_key: config[:lookup_key],
        transfer_lookup_key: true
      )
      puts "  ✓ Created #{config[:lookup_key]}: #{price.id} ($#{config[:amount] / 100}/#{config[:interval]})"
    end

    puts "\nDone! Prices are ready. No ENV vars needed — prices are resolved via lookup keys at runtime."
  end
end

def find_or_create_product(name, description)
  products = Stripe::Product.list(limit: 100, active: true)
  existing = products.data.find { |p| p.name == name }

  if existing
    puts "  ✓ Product '#{name}' already exists: #{existing.id}"
    existing
  else
    product = Stripe::Product.create(name: name, description: description)
    puts "  ✓ Created product '#{name}': #{product.id}"
    product
  end
end
