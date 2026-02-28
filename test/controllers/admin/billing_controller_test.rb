require "test_helper"

class Admin::BillingControllerTest < ActionDispatch::IntegrationTest
  setup { @admin_user = admin_users(:one) }

  # ── Authentication ──

  test "all POST actions redirect to sign-in when unauthenticated" do
    post setup_stripe_admin_billing_path
    assert_redirected_to new_admin_session_path

    post configure_portal_admin_billing_path
    assert_redirected_to new_admin_session_path

    post sync_all_organizations_admin_billing_path
    assert_redirected_to new_admin_session_path

    post sync_organization_admin_billing_path, params: { organization_id: organizations(:one).id }
    assert_redirected_to new_admin_session_path
  end

  # ── show ──

  test "show renders successfully with Stripe status" do
    sign_in_as_admin(@admin_user)

    mock_status = { complete: true, prices: [], missing_keys: [] }
    StripeAdminService.stub :verify_products_and_prices, mock_status do
      get admin_billing_path
      assert_response :success
    end
  end

  # ── setup_stripe ──

  test "setup_stripe redirects with notice on success" do
    sign_in_as_admin(@admin_user)

    mock_result = { success: true, created: [ "starter_monthly" ], skipped: [ "pro_annual" ] }
    StripeAdminService.stub :setup_products_and_prices!, mock_result do
      post setup_stripe_admin_billing_path

      assert_redirected_to admin_billing_path
      assert_match "Stripe setup complete", flash[:notice]
    end
  end

  test "setup_stripe redirects with alert on failure" do
    sign_in_as_admin(@admin_user)

    mock_result = { success: false, message: "API key invalid", created: [], skipped: [] }
    StripeAdminService.stub :setup_products_and_prices!, mock_result do
      post setup_stripe_admin_billing_path

      assert_redirected_to admin_billing_path
      assert_match "Stripe setup failed", flash[:alert]
    end
  end

  # ── configure_portal ──

  test "configure_portal redirects with notice on success" do
    sign_in_as_admin(@admin_user)

    mock_result = { success: true, configuration_id: "bpc_test123", message: "Created" }
    StripeAdminService.stub :configure_billing_portal!, mock_result do
      post configure_portal_admin_billing_path

      assert_redirected_to admin_billing_path
      assert_match "bpc_test123", flash[:notice]
    end
  end

  test "configure_portal redirects with alert on failure" do
    sign_in_as_admin(@admin_user)

    mock_result = { success: false, message: "Forbidden" }
    StripeAdminService.stub :configure_billing_portal!, mock_result do
      post configure_portal_admin_billing_path

      assert_redirected_to admin_billing_path
      assert_match "Portal configuration failed", flash[:alert]
    end
  end

  # ── sync_all_organizations ──

  test "sync_all_organizations redirects with notice on success" do
    sign_in_as_admin(@admin_user)

    mock_result = { success: true, synced: 3, failed: 0, errors: [], details: [ { changed: true }, { changed: false }, { changed: true } ] }
    StripeAdminService.stub :sync_all_organizations!, mock_result do
      post sync_all_organizations_admin_billing_path

      assert_redirected_to admin_billing_path
      assert_match "Synced 3 organizations", flash[:notice]
    end
  end

  test "sync_all_organizations redirects with alert on failure" do
    sign_in_as_admin(@admin_user)

    mock_result = { success: false, message: "Database error" }
    StripeAdminService.stub :sync_all_organizations!, mock_result do
      post sync_all_organizations_admin_billing_path

      assert_redirected_to admin_billing_path
      assert_match "Sync failed", flash[:alert]
    end
  end

  # ── sync_organization ──

  test "sync_organization redirects with notice when plan changed" do
    sign_in_as_admin(@admin_user)
    org = organizations(:one)

    mock_result = { success: true, old_plan: "free", new_plan: "starter", changed: true }
    StripeAdminService.stub :sync_organization!, mock_result do
      post sync_organization_admin_billing_path, params: { organization_id: org.id }

      assert_redirected_to admin_billing_path
      assert_match "plan updated", flash[:notice]
    end
  end

  test "sync_organization redirects with notice when already in sync" do
    sign_in_as_admin(@admin_user)
    org = organizations(:one)

    mock_result = { success: true, old_plan: "starter", new_plan: "starter", changed: false }
    StripeAdminService.stub :sync_organization!, mock_result do
      post sync_organization_admin_billing_path, params: { organization_id: org.id }

      assert_redirected_to admin_billing_path
      assert_match "already in sync", flash[:notice]
    end
  end

  test "sync_organization redirects with alert for invalid org ID" do
    sign_in_as_admin(@admin_user)

    post sync_organization_admin_billing_path, params: { organization_id: "nonexistent-uuid" }

    assert_redirected_to admin_billing_path
    assert_match "Organization not found", flash[:alert]
  end

  test "sync_organization redirects with alert on service failure" do
    sign_in_as_admin(@admin_user)
    org = organizations(:one)

    mock_result = { success: false, message: "Stripe API error" }
    StripeAdminService.stub :sync_organization!, mock_result do
      post sync_organization_admin_billing_path, params: { organization_id: org.id }

      assert_redirected_to admin_billing_path
      assert_match "Sync failed", flash[:alert]
    end
  end
end
