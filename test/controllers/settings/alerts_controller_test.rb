require "test_helper"

class Settings::AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @org = organizations(:one)
  end

  test "should get show" do
    get settings_alerts_path
    assert_response :success
    assert_match "Alert Settings", response.body
  end

  test "should update preferences" do
    expected_jobs = @org.contracts.where(status: Contract::ACTIVE_STATUSES).count

    assert_enqueued_jobs expected_jobs, only: GenerateContractAlertsJob do
      patch settings_alerts_path, params: {
        alert_preference: {
          email_enabled: false,
          in_app_enabled: true,
          days_before_renewal: 45,
          days_before_expiry: 7
        }
      }
    end

    assert_redirected_to settings_alerts_path
    pref = AlertPreference.for(users(:one), organizations(:one))
    assert_equal false, pref.email_enabled
    assert_equal true, pref.in_app_enabled
    assert_equal 45, pref.days_before_renewal
    assert_equal 7, pref.days_before_expiry
  end

  test "rejects invalid preferences" do
    assert_no_enqueued_jobs only: GenerateContractAlertsJob do
      patch settings_alerts_path, params: {
        alert_preference: {
          days_before_renewal: 0,
          days_before_expiry: -5
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should update lease alert preferences" do
    patch settings_alerts_path, params: {
      alert_preference: {
        days_before_option_exercise: 120,
        days_before_rent_escalation: 45,
        days_before_cam_reconciliation: 60,
        days_before_milestone: 21
      }
    }

    assert_redirected_to settings_alerts_path
    pref = AlertPreference.for(users(:one), organizations(:one))
    assert_equal 120, pref.days_before_option_exercise
    assert_equal 45, pref.days_before_rent_escalation
    assert_equal 60, pref.days_before_cam_reconciliation
    assert_equal 21, pref.days_before_milestone
  end

  test "shows lease alert settings section" do
    get settings_alerts_path
    assert_response :success
    assert_match "Lease Alert Timing", response.body
    assert_match "days_before_option_exercise", response.body
  end

  test "does not affect other organization preferences" do
    other_pref = AlertPreference.create!(
      user: users(:two),
      organization: organizations(:two),
      email_enabled: true,
      days_before_renewal: 30,
      days_before_expiry: 14
    )

    patch settings_alerts_path, params: {
      alert_preference: {
        email_enabled: false,
        days_before_renewal: 60
      }
    }

    other_pref.reload
    assert_equal true, other_pref.email_enabled
    assert_equal 30, other_pref.days_before_renewal
  end

  test "requires authentication" do
    sign_out
    get settings_alerts_path
    assert_response :redirect
  end

  test "old alert_preference path redirects to settings alerts" do
    get "/alert_preference"
    assert_response :redirect
    assert_redirected_to "/settings/alerts"
  end
end
