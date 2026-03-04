require "test_helper"

class AiUsageLogTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @contract = contracts(:hvac_maintenance)
  end

  test "computes total tokens before validation" do
    log = AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_model: "claude-sonnet-4-20250514",
      input_tokens: 100,
      output_tokens: 50,
      extraction_mode: "full",
      success: true
    )

    assert_equal 150, log.total_tokens
  end

  test "total_cost computes from scope" do
    AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_model: "claude-sonnet-4-20250514",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000,
      extraction_mode: "full",
      success: true
    )

    assert_equal 18.0, AiUsageLog.total_cost.round(2)
  end

  test "total_cost uses linked config pricing when present" do
    premium_config = AiExtractionConfig.create!(
      extraction_type: "generic_full",
      ai_model: "claude-sonnet-4-20250514",
      max_tokens: 4096,
      input_cost_per_million: 10.0,
      output_cost_per_million: 20.0,
      version: 99,
      active: false
    )

    AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_model: premium_config.ai_model,
      input_tokens: 1_000_000,
      output_tokens: 1_000_000,
      extraction_mode: "full",
      success: true,
      ai_extraction_config: premium_config
    )

    assert_equal 30.0, AiUsageLog.total_cost.round(2)
  end
end
