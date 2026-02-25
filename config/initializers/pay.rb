Pay.setup do |config|
  config.business_name = "PactBadger"
  config.business_address = ""
  config.application_name = "PactBadger"
  config.support_email = "support@pactbadger.com"
end

# Sync organization plan when Pay subscription changes.
# Uses to_prepare + concern (idempotent include) to avoid circular
# dependency during eager loading that occurs with on_load(:active_record).
Rails.application.config.to_prepare do
  Pay::Subscription.include(PaySubscriptionCallbacks) unless Pay::Subscription.include?(PaySubscriptionCallbacks)
end
