class AiExtractionConfig < ApplicationRecord
  EXTRACTION_TYPES = %w[generic_full generic_incremental lease_full lease_incremental].freeze

  # Curated list of available Anthropic models (newest first).
  # Update this list when new models are released and deploy.
  AVAILABLE_MODELS = [
    { id: "claude-opus-4-6",            label: "Claude Opus 4.6",              input_cost_per_million: 5.0,  output_cost_per_million: 25.0 },
    { id: "claude-sonnet-4-6",          label: "Claude Sonnet 4.6",            input_cost_per_million: 3.0,  output_cost_per_million: 15.0 },
    { id: "claude-sonnet-4-5-20250929", label: "Claude Sonnet 4.5",            input_cost_per_million: 3.0,  output_cost_per_million: 15.0 },
    { id: "claude-opus-4-5-20251101",   label: "Claude Opus 4.5",              input_cost_per_million: 5.0,  output_cost_per_million: 25.0 },
    { id: "claude-opus-4-1-20250805",   label: "Claude Opus 4.1",              input_cost_per_million: 15.0, output_cost_per_million: 75.0 },
    { id: "claude-sonnet-4-20250514",   label: "Claude Sonnet 4",              input_cost_per_million: 3.0,  output_cost_per_million: 15.0 },
    { id: "claude-opus-4-20250514",     label: "Claude Opus 4",                input_cost_per_million: 15.0, output_cost_per_million: 75.0 },
    { id: "claude-3-haiku-20240307",    label: "Claude Haiku 3 (deprecated)",  input_cost_per_million: 0.25, output_cost_per_million: 1.25 }
  ].freeze

  AVAILABLE_MODEL_IDS = AVAILABLE_MODELS.map { |m| m[:id] }.freeze

  DEFAULT_REQUEST_TIMEOUT = 120 # seconds — gem default
  LEASE_REQUEST_TIMEOUT = 300   # seconds — lease extractions need more time

  # Fallback defaults if no active config exists in DB
  DEFAULTS = {
    "generic_full" => { ai_model: "claude-sonnet-4-20250514", max_tokens: 4096, input_cost_per_million: 3.0, output_cost_per_million: 15.0, request_timeout: DEFAULT_REQUEST_TIMEOUT },
    "generic_incremental" => { ai_model: "claude-sonnet-4-20250514", max_tokens: 4096, input_cost_per_million: 3.0, output_cost_per_million: 15.0, request_timeout: DEFAULT_REQUEST_TIMEOUT },
    "lease_full" => { ai_model: "claude-sonnet-4-20250514", max_tokens: 16384, input_cost_per_million: 3.0, output_cost_per_million: 15.0, request_timeout: LEASE_REQUEST_TIMEOUT },
    "lease_incremental" => { ai_model: "claude-sonnet-4-20250514", max_tokens: 16384, input_cost_per_million: 3.0, output_cost_per_million: 15.0, request_timeout: LEASE_REQUEST_TIMEOUT }
  }.freeze

  # Returns [[label, id], ...] for use with form.select
  def self.model_options_for_select
    AVAILABLE_MODELS.map { |m| [ m[:label], m[:id] ] }
  end

  # Returns { input_cost_per_million:, output_cost_per_million: } for a given model ID, or nil
  def self.model_pricing(model_id)
    model = AVAILABLE_MODELS.find { |m| m[:id] == model_id }
    return nil unless model

    { input_cost_per_million: model[:input_cost_per_million], output_cost_per_million: model[:output_cost_per_million] }
  end

  # Returns a JSON-serializable hash of model_id => { input:, output: } for Stimulus pricing auto-fill
  def self.model_pricing_json
    AVAILABLE_MODELS.each_with_object({}) do |m, hash|
      hash[m[:id]] = { input: m[:input_cost_per_million], output: m[:output_cost_per_million] }
    end
  end

  belongs_to :created_by, class_name: "AdminUser", optional: true
  has_many :ai_usage_logs, dependent: :nullify

  validates :extraction_type, presence: true, inclusion: { in: EXTRACTION_TYPES }
  validates :ai_model, presence: true, inclusion: { in: AVAILABLE_MODEL_IDS }
  validates :max_tokens, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :temperature, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true
  validates :top_p, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true
  validates :top_k, numericality: { greater_than_or_equal_to: 1, only_integer: true }, allow_nil: true
  validates :input_cost_per_million, presence: true, numericality: { greater_than: 0 }
  validates :output_cost_per_million, presence: true, numericality: { greater_than: 0 }
  validates :request_timeout, numericality: { greater_than_or_equal_to: 30, less_than_or_equal_to: 600, only_integer: true }, allow_nil: true
  validates :version, presence: true, uniqueness: { scope: :extraction_type }

  scope :active, -> { where(active: true) }
  scope :for_type, ->(type) { where(extraction_type: type) }
  scope :latest_version, ->(type) { for_type(type).order(version: :desc).first }

  before_validation :set_version_number, on: :create

  # Returns the active config for a given extraction type, with hardcoded fallback
  def self.active_for(extraction_type)
    config = active.for_type(extraction_type).first
    return config if config

    # Build a transient (unsaved) config from defaults as safety net
    defaults = DEFAULTS[extraction_type]
    return nil unless defaults

    new(extraction_type: extraction_type, **defaults, version: 0, active: true)
  end

  # Activate this config version, deactivating all others of the same type
  def activate!
    transaction do
      self.class.for_type(extraction_type).where(active: true).update_all(active: false)
      update!(active: true)
    end
  end

  # Label for display
  def type_label
    extraction_type.titleize
  end

  # Resolved timeout in seconds — uses configured value, or a sensible default
  def resolved_timeout
    return request_timeout if request_timeout.present?

    extraction_type&.start_with?("lease") ? LEASE_REQUEST_TIMEOUT : DEFAULT_REQUEST_TIMEOUT
  end

  # Build API parameters hash (only non-nil sampling params included)
  def api_parameters
    params = { model: ai_model, max_tokens: max_tokens }
    params[:temperature] = temperature.to_f if temperature.present?
    params[:top_p] = top_p.to_f if top_p.present?
    params[:top_k] = top_k if top_k.present?
    params
  end

  private

  def set_version_number
    return if version.present?

    max_version = self.class.for_type(extraction_type).maximum(:version) || 0
    self.version = max_version + 1
  end
end
