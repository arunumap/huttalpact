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
end
