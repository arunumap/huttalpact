require "test_helper"

class Admin::AiExtractionConfigsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    @config = ai_extraction_configs(:generic_full_v1)
  end

  # --- Auth ---

  test "requires admin authentication for index" do
    get admin_ai_extraction_configs_path
    assert_redirected_to new_admin_session_path
  end

  # --- Index ---

  test "index shows all extraction types" do
    sign_in_as_admin(@admin_user)
    get admin_ai_extraction_configs_path
    assert_response :success
    assert_select "h3", text: "Generic Full"
    assert_select "h3", text: "Lease Full"
    assert_select "h3", text: "Generic Incremental"
    assert_select "h3", text: "Lease Incremental"
  end

  # --- Show ---

  test "show displays config version details" do
    sign_in_as_admin(@admin_user)
    get admin_ai_extraction_config_path(@config)
    assert_response :success
    assert_select "dd", text: @config.ai_model
  end

  # --- New ---

  test "new pre-fills from active config" do
    sign_in_as_admin(@admin_user)
    get new_admin_ai_extraction_config_path(extraction_type: "generic_full")
    assert_response :success
    # Verify the AI model field is a select dropdown, not a text input
    assert_select "select[name='ai_extraction_config[ai_model]']"
    # Verify known models appear as options
    assert_select "select[name='ai_extraction_config[ai_model]'] option[value='claude-sonnet-4-6']"
    assert_select "select[name='ai_extraction_config[ai_model]'] option[value='claude-opus-4-6']"
  end

  test "new rejects invalid extraction type" do
    sign_in_as_admin(@admin_user)
    get new_admin_ai_extraction_config_path(extraction_type: "bogus")
    assert_redirected_to admin_ai_extraction_configs_path
  end

  # --- Create ---

  test "create adds a new config version" do
    sign_in_as_admin(@admin_user)
    assert_difference "AiExtractionConfig.count", 1 do
      post admin_ai_extraction_configs_path, params: {
        ai_extraction_config: {
          extraction_type: "generic_full",
          ai_model: "claude-opus-4-20250514",
          max_tokens: 16384,
          temperature: 0.2,
          input_cost_per_million: 15.0,
          output_cost_per_million: 75.0,
          notes: "Testing Opus model"
        }
      }
    end
    config = AiExtractionConfig.order(:created_at).last
    assert_redirected_to admin_ai_extraction_config_path(config)
    assert_equal "claude-opus-4-20250514", config.ai_model
    assert_equal 16384, config.max_tokens
    assert_not config.active?
  end

  test "create and activate" do
    sign_in_as_admin(@admin_user)
    post admin_ai_extraction_configs_path, params: {
      activate: "1",
      ai_extraction_config: {
        extraction_type: "generic_full",
        ai_model: "claude-opus-4-20250514",
        max_tokens: 16384,
        input_cost_per_million: 15.0,
        output_cost_per_million: 75.0
      }
    }
    config = AiExtractionConfig.order(:created_at).last
    assert config.active?
    assert_not @config.reload.active?
  end

  test "create with invalid params renders new" do
    sign_in_as_admin(@admin_user)
    assert_no_difference "AiExtractionConfig.count" do
      post admin_ai_extraction_configs_path, params: {
        ai_extraction_config: {
          extraction_type: "generic_full",
          ai_model: "",
          max_tokens: -1,
          input_cost_per_million: 3.0,
          output_cost_per_million: 15.0
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # --- Activate ---

  test "activate switches active config" do
    sign_in_as_admin(@admin_user)
    inactive = ai_extraction_configs(:generic_full_v2_inactive)
    post activate_admin_ai_extraction_config_path(inactive)
    assert_redirected_to admin_ai_extraction_configs_path
    assert inactive.reload.active?
    assert_not @config.reload.active?
  end
end
