Pay.setup do |config|
  config.business_name = "HuttalPact"
  config.business_address = ""
  config.application_name = "HuttalPact"
  config.support_email = "support@huttalpact.com"
end

# Sync organization plan when Pay subscription changes
ActiveSupport.on_load(:active_record) do
  Pay::Subscription.after_commit on: %i[create update] do
    owner = customer&.owner
    owner&.sync_plan_from_subscription! if owner.is_a?(Organization)
  rescue => e
    Rails.logger.error("Pay subscription sync error (create/update): #{e.message}")
  end

  Pay::Subscription.after_commit on: :destroy do
    owner = customer&.owner
    owner&.sync_plan_from_subscription! if owner.is_a?(Organization)
  rescue => e
    Rails.logger.error("Pay subscription sync error (destroy): #{e.message}")
  end
end
