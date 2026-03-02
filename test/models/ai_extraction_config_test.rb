require "test_helper"

class AiExtractionConfigTest < ActiveSupport::TestCase
  setup do
    @config = ai_extraction_configs(:generic_full_v1)
  end

  # --- Validations ---

  test "valid config is valid" do
    assert @config.valid?
  end

  test "requires extraction_type" do
    @config.extraction_type = nil
    assert_not @config.valid?
  end

  test "extraction_type must be in EXTRACTION_TYPES" do
    @config.extraction_type = "bogus"
    assert_not @config.valid?
  end

  test "requires ai_model" do
    @config.ai_model = nil
    assert_not @config.valid?
  end

  test "requires max_tokens > 0" do
    @config.max_tokens = 0
    assert_not @config.valid?
    @config.max_tokens = -1
    assert_not @config.valid?
  end

  test "temperature must be between 0 and 1" do
    @config.temperature = -0.1
    assert_not @config.valid?
    @config.temperature = 1.1
    assert_not @config.valid?
    @config.temperature = 0.5
    assert @config.valid?
  end

  test "temperature can be nil" do
    @config.temperature = nil
    assert @config.valid?
  end

  test "top_p must be between 0 and 1" do
    @config.top_p = 1.5
    assert_not @config.valid?
  end

  test "top_k must be >= 1" do
    @config.top_k = 0
    assert_not @config.valid?
    @config.top_k = 1
    assert @config.valid?
  end

  test "request_timeout must be between 30 and 600" do
    @config.request_timeout = 29
    assert_not @config.valid?
    @config.request_timeout = 601
    assert_not @config.valid?
    @config.request_timeout = 300
    assert @config.valid?
  end

  test "request_timeout can be nil" do
    @config.request_timeout = nil
    assert @config.valid?
  end

  test "request_timeout must be an integer" do
    @config.request_timeout = 120.5
    assert_not @config.valid?
  end

  test "requires positive cost rates" do
    @config.input_cost_per_million = 0
    assert_not @config.valid?
    @config.input_cost_per_million = 3.0
    @config.output_cost_per_million = -1
    assert_not @config.valid?
  end

  test "version must be unique per extraction_type" do
    dupe = AiExtractionConfig.new(
      extraction_type: @config.extraction_type,
      ai_model: "claude-sonnet-4-20250514",
      max_tokens: 1000,
      input_cost_per_million: 1.0,
      output_cost_per_million: 1.0,
      version: @config.version
    )
    assert_not dupe.valid?
    assert_includes dupe.errors[:version], "has already been taken"
  end

  # --- active_for ---

  test "active_for returns the active config for a type" do
    config = AiExtractionConfig.active_for("generic_full")
    assert_equal @config, config
    assert config.active?
  end

  test "active_for returns fallback when no active config exists" do
    AiExtractionConfig.where(extraction_type: "generic_full").update_all(active: false)
    config = AiExtractionConfig.active_for("generic_full")
    assert_not_nil config
    assert_not config.persisted?
    assert_equal "claude-sonnet-4-20250514", config.ai_model
  end

  test "active_for returns nil for unknown type" do
    assert_nil AiExtractionConfig.active_for("bogus_type")
  end

  # --- activate! ---

  test "activate! deactivates other configs of same type and activates self" do
    inactive = ai_extraction_configs(:generic_full_v2_inactive)
    assert_not inactive.active?
    assert @config.active?

    inactive.activate!

    assert inactive.reload.active?
    assert_not @config.reload.active?
  end

  test "activate! does not affect configs of other types" do
    lease_config = ai_extraction_configs(:lease_full_v1)
    assert lease_config.active?

    inactive = ai_extraction_configs(:generic_full_v2_inactive)
    inactive.activate!

    assert lease_config.reload.active?
  end

  # --- set_version_number ---

  test "auto-sets version number on create" do
    config = AiExtractionConfig.create!(
      extraction_type: "generic_full",
      ai_model: "claude-sonnet-4-6",
      max_tokens: 2000,
      input_cost_per_million: 3.0,
      output_cost_per_million: 15.0
    )
    # generic_full already has v1 and v2 from fixtures
    assert_equal 3, config.version
  end

  test "does not override explicit version" do
    config = AiExtractionConfig.new(
      extraction_type: "generic_full",
      ai_model: "claude-sonnet-4-6",
      max_tokens: 1000,
      input_cost_per_million: 3.0,
      output_cost_per_million: 15.0,
      version: 99
    )
    config.save!
    assert_equal 99, config.version
  end

  # --- api_parameters ---

  test "api_parameters includes model and max_tokens" do
    params = @config.api_parameters
    assert_equal "claude-sonnet-4-20250514", params[:model]
    assert_equal 4096, params[:max_tokens]
    assert_not params.key?(:temperature)
    assert_not params.key?(:top_p)
    assert_not params.key?(:top_k)
  end

  test "api_parameters includes sampling params when set" do
    @config.temperature = 0.7
    @config.top_p = 0.9
    @config.top_k = 50
    params = @config.api_parameters
    assert_equal 0.7, params[:temperature]
    assert_equal 0.9, params[:top_p]
    assert_equal 50, params[:top_k]
  end

  # --- resolved_timeout ---

  test "resolved_timeout returns configured value when present" do
    @config.request_timeout = 180
    assert_equal 180, @config.resolved_timeout
  end

  test "resolved_timeout returns default for generic types when nil" do
    @config.request_timeout = nil
    @config.extraction_type = "generic_full"
    assert_equal AiExtractionConfig::DEFAULT_REQUEST_TIMEOUT, @config.resolved_timeout
  end

  test "resolved_timeout returns lease default for lease types when nil" do
    @config.request_timeout = nil
    @config.extraction_type = "lease_full"
    assert_equal AiExtractionConfig::LEASE_REQUEST_TIMEOUT, @config.resolved_timeout
  end

  test "resolved_timeout returns lease default for lease_incremental when nil" do
    @config.request_timeout = nil
    @config.extraction_type = "lease_incremental"
    assert_equal AiExtractionConfig::LEASE_REQUEST_TIMEOUT, @config.resolved_timeout
  end

  # --- type_label ---

  test "type_label returns titleized extraction_type" do
    assert_equal "Generic Full", @config.type_label
  end

  # --- AVAILABLE_MODELS ---

  test "AVAILABLE_MODELS contains expected models" do
    assert_equal 8, AiExtractionConfig::AVAILABLE_MODELS.length
    ids = AiExtractionConfig::AVAILABLE_MODEL_IDS
    assert_includes ids, "claude-opus-4-6"
    assert_includes ids, "claude-sonnet-4-6"
    assert_includes ids, "claude-sonnet-4-5-20250929"
    assert_includes ids, "claude-opus-4-5-20251101"
    assert_includes ids, "claude-opus-4-1-20250805"
    assert_includes ids, "claude-sonnet-4-20250514"
    assert_includes ids, "claude-opus-4-20250514"
    assert_includes ids, "claude-3-haiku-20240307"
  end

  test "ai_model must be in AVAILABLE_MODELS" do
    @config.ai_model = "unknown-model-123"
    assert_not @config.valid?
    assert_includes @config.errors[:ai_model], "is not included in the list"
  end

  test "ai_model accepts all available models" do
    AiExtractionConfig::AVAILABLE_MODEL_IDS.each do |model_id|
      @config.ai_model = model_id
      @config.valid?
      assert_not_includes(@config.errors[:ai_model], "is not included in the list",
        "Expected #{model_id} to be valid")
    end
  end

  # --- model_options_for_select ---

  test "model_options_for_select returns label-id pairs" do
    options = AiExtractionConfig.model_options_for_select
    assert_kind_of Array, options
    assert_equal 8, options.length
    first = options.first
    assert_equal [ "Claude Opus 4.6", "claude-opus-4-6" ], first
  end

  # --- model_pricing ---

  test "DEFAULTS include request_timeout for all types" do
    AiExtractionConfig::DEFAULTS.each do |type, defaults|
      assert defaults.key?(:request_timeout), "DEFAULTS[#{type}] missing request_timeout"
      assert_kind_of Integer, defaults[:request_timeout]
    end
  end

  test "model_pricing returns costs for known model" do
    pricing = AiExtractionConfig.model_pricing("claude-sonnet-4-6")
    assert_equal 3.0, pricing[:input_cost_per_million]
    assert_equal 15.0, pricing[:output_cost_per_million]
  end

  test "model_pricing returns nil for unknown model" do
    assert_nil AiExtractionConfig.model_pricing("nonexistent-model")
  end

  # --- model_pricing_json ---

  test "model_pricing_json returns hash keyed by model id" do
    json = AiExtractionConfig.model_pricing_json
    assert_kind_of Hash, json
    assert_equal 8, json.keys.length
    assert_equal({ input: 5.0, output: 25.0 }, json["claude-opus-4-6"])
  end
end
