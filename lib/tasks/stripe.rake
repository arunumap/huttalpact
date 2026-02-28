namespace :stripe do
  desc "Create Stripe products and prices with lookup keys for PactBadger plans"
  task setup: :environment do
    require "stripe"

    result = StripeAdminService.verify_products_and_prices

    if result[:error]
      puts "\n✗ Error checking Stripe: #{result[:message]}"
      exit 1
    end

    if result[:complete]
      puts "\n✓ All prices already exist with correct lookup keys:"
      result[:prices].each do |p|
        puts "  #{p[:lookup_key]}: #{p[:price_id]} ($#{p[:amount].to_i / 100}/#{p[:interval]})"
      end
      puts "\nNo changes needed."
      return
    end

    result = StripeAdminService.setup_products_and_prices!

    if result[:success]
      result[:created].each { |key| puts "  ✓ Created #{key}" }
      result[:skipped].each { |key| puts "  ✓ #{key} already exists, skipping" }
      puts "\nDone! Prices are ready."
    else
      puts "\n✗ Error: #{result[:message]}"
      exit 1
    end
  end

  desc "Create or update the Stripe Customer Portal configuration (payment methods + invoices only)"
  task configure_portal: :environment do
    require "stripe"

    result = StripeAdminService.configure_billing_portal!

    if result[:success]
      puts "\n✓ Portal Configuration ID: #{result[:configuration_id]}"
      puts "\nAdd this to your Rails credentials:"
      puts "  stripe:"
      puts "    portal_configuration_id: #{result[:configuration_id]}"
      puts "\nRun: EDITOR=\"code --wait\" bin/rails credentials:edit"
    else
      puts "\n✗ Error: #{result[:message]}"
      exit 1
    end
  end
end
