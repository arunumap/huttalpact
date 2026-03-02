require "test_helper"

class AiUsageLogEstimatedCostTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @contract = contracts(:hvac_maintenance)
  end

  test "estimated_cost uses hardcoded rates when no config linked" do
    log = AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_model: "claude-sonnet-4-20250514",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000,
      extraction_mode: "full",
      success: true
    )
    assert_nil log.ai_extraction_config
    assert_in_delta 18.0, log.estimated_cost, 0.01
  end

  test "estimated_cost uses config rates when linked" do
    config = ai_extraction_configs(:generic_full_v1)
    log = AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_model: config.ai_model,
      input_tokens: 1_000_000,
      output_tokens: 1_000_000,
      extraction_mode: "full",
      success: true,
      ai_extraction_config: config
    )
    expected = (1_000_000 / 1_000_000.0 * config.input_cost_per_million) +
               (1_000_000 / 1_000_000.0 * config.output_cost_per_million)
    assert_in_delta expected, log.estimated_cost, 0.01
  end
end
