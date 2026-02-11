Sentry.init do |config|
  config.dsn = Rails.application.credentials.dig(:sentry, :dsn)
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.send_default_pii = false

  # Sample 10% of requests for performance monitoring — adjust as needed
  config.traces_sample_rate = 0.1

  # Exclude expected business-logic errors that are not bugs
  config.excluded_exceptions += %w[
    ContractAiExtractorService::ExtractionLimitReachedError
    ContractTextExtractorService::UnsupportedFormatError
  ]
end
