require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "should get index" do
    get alerts_path
    assert_response :success
  end

  test "index shows user's alerts" do
    get alerts_path
    assert_response :success
    assert_match "Landscaping Services", response.body
  end

  test "index does not show other org's alerts" do
    get alerts_path
    assert_no_match(/Office Lease/, response.body)
  end

  test "index defaults to active alerts filter" do
    get alerts_path
    assert_response :success
    assert_select '[data-alerts-bucket-multiselect="true"] input[name="buckets[]"][value="active"][checked="checked"]', count: 1
    assert_select '[data-controller="multiselect-summary"] button[data-multiselect-summary-value-param="active"]', count: 1
    assert_select alert_frame_selector(:expiry_warning), count: 1
    assert_select alert_frame_selector(:overdue_alert), count: 1
    assert_select alert_frame_selector(:sent_alert), count: 1
    assert_select alert_frame_selector(:renewal_upcoming), count: 0
    assert_select alert_frame_selector(:scheduled_far_future), count: 0
  end

  test "index filters upcoming alerts" do
    get alerts_path, params: { buckets: [ "upcoming" ] }
    assert_response :success
    assert_select 'input[name="buckets[]"][value="upcoming"][checked="checked"]', count: 1
    assert_select alert_frame_selector(:renewal_upcoming), count: 1
    assert_select alert_frame_selector(:expiry_warning), count: 0
    assert_select alert_frame_selector(:scheduled_far_future), count: 0
  end

  test "index filters scheduled alerts" do
    get alerts_path, params: { buckets: [ "scheduled" ] }
    assert_response :success
    assert_select 'input[name="buckets[]"][value="scheduled"][checked="checked"]', count: 1
    assert_select alert_frame_selector(:scheduled_far_future), count: 1
    assert_select alert_frame_selector(:renewal_upcoming), count: 0
    assert_select alert_frame_selector(:expiry_warning), count: 0
  end

  test "index filters overdue alerts" do
    stale_alert = create_alert_for_current_user(trigger_date: 20.days.ago.to_date, alert_type: "expiry_warning")

    get alerts_path, params: { buckets: [ "overdue" ] }
    assert_response :success
    assert_select 'input[name="buckets[]"][value="overdue"][checked="checked"]', count: 1
    assert_select alert_frame_selector(stale_alert), count: 1
    assert_select alert_frame_selector(:overdue_alert), count: 0
    assert_select alert_frame_selector(:sent_alert), count: 0
    assert_select alert_frame_selector(:expiry_warning), count: 0
  end

  test "index filters due today alerts by alert window end date" do
    due_today_alert = create_alert_for_current_user(trigger_date: 14.days.ago.to_date, alert_type: "expiry_warning")

    get alerts_path, params: { buckets: [ "today" ] }
    assert_response :success
    assert_select 'input[name="buckets[]"][value="today"][checked="checked"]', count: 1
    assert_select alert_frame_selector(due_today_alert), count: 1
    assert_select alert_frame_selector(:expiry_warning), count: 0
  end

  test "active milestone reminder uses preference window messaging" do
    preference = AlertPreference.for(users(:one), organizations(:one))
    preference.update!(days_before_milestone: 14)
    milestone_alert = create_alert_for_current_user(
      trigger_date: 2.days.ago.to_date,
      alert_type: "milestone_reminder",
      message: "Custom — milestone reminder"
    )

    get alerts_path, params: { buckets: [ "active" ] }
    assert_response :success
    assert_select alert_frame_selector(milestone_alert), count: 1
    assert_match "in 12 days", response.body
    assert_no_match(/12 days overdue/i, response.body)
  end

  test "index falls back to active filter for invalid bucket" do
    get alerts_path, params: { buckets: [ "invalid" ] }
    assert_response :success
    assert_select 'input[name="buckets[]"][value="active"][checked="checked"]', count: 1
  end

  test "index supports selecting multiple buckets" do
    get alerts_path, params: { buckets: [ "active", "upcoming" ] }

    assert_response :success
    assert_select 'input[name="buckets[]"][value="active"][checked="checked"]', count: 1
    assert_select 'input[name="buckets[]"][value="upcoming"][checked="checked"]', count: 1
    assert_select alert_frame_selector(:expiry_warning), count: 1
    assert_select alert_frame_selector(:renewal_upcoming), count: 1
  end

  test "bucket summary collapses additional selections into a more pill" do
    get alerts_path, params: { buckets: [ "active", "overdue", "today", "upcoming" ] }

    assert_response :success
    assert_select '[data-alerts-bucket-multiselect="true"] button[data-multiselect-summary-value-param]', count: 3
    assert_select '[data-alerts-bucket-multiselect="true"] span', text: /\+ 1 more/
  end

  test "index filters alerts by selected contracts" do
    Membership.find_or_create_by!(user: users(:two), organization: organizations(:one)) do |membership|
      membership.role = Membership::MEMBER_ROLE
    end

    other_user_contract = Contract.create!(
      organization: organizations(:one),
      title: "Vendor Contract Uploaded by Another User",
      vendor_name: "Shared Vendor",
      status: "active",
      contract_type: "service_agreement",
      direction: "inbound",
      start_date: Date.current,
      end_date: 1.year.from_now.to_date,
      extraction_status: "pending",
      uploaded_by: users(:two)
    )
    other_uploader_alert = Alert.create!(
      organization: organizations(:one),
      contract: other_user_contract,
      alert_type: "expiry_warning",
      trigger_date: Date.current,
      status: "pending",
      message: "Shared vendor expires soon"
    )
    AlertRecipient.create!(alert: other_uploader_alert, user: users(:one), channel: "in_app")

    get alerts_path, params: { contract_ids: [ contracts(:landscaping).id.to_s ] }

    assert_response :success
    assert_select alert_frame_selector(:expiry_warning), count: 1
    assert_select alert_frame_selector(other_uploader_alert), count: 0
    assert_select 'input[name="contract_ids[]"][value=?][checked="checked"]', contracts(:landscaping).id.to_s, count: 1
    assert_select "button[data-multiselect-summary-value-param='#{contracts(:landscaping).id}']", text: /Landscaping Services/
  end

  test "index shows all buckets when filter is present but no buckets are selected" do
    get alerts_path, params: { buckets_filter_present: "1" }

    assert_response :success
    assert_select alert_frame_selector(:expiry_warning), count: 1
    assert_select alert_frame_selector(:renewal_upcoming), count: 1
    assert_select alert_frame_selector(:scheduled_far_future), count: 1
  end

  test "index supports selecting multiple contracts" do
    other_alert = create_alert_for_current_user(
      trigger_date: Date.current,
      alert_type: "expiry_warning",
      contract: contracts(:hvac_maintenance)
    )

    get alerts_path, params: { contract_ids: [ contracts(:landscaping).id.to_s, contracts(:hvac_maintenance).id.to_s ] }

    assert_response :success
    assert_select alert_frame_selector(:expiry_warning), count: 1
    assert_select alert_frame_selector(other_alert), count: 1
  end

  test "contract summary collapses additional selections into a more pill" do
    get alerts_path, params: { contract_ids: [
      contracts(:hvac_maintenance).id.to_s,
      contracts(:landscaping).id.to_s,
      contracts(:expired_insurance).id.to_s,
      contracts(:commercial_lease).id.to_s
    ] }

    assert_response :success
    assert_select '[data-alerts-contract-multiselect="true"] button[data-multiselect-summary-value-param]', count: 3
    assert_select '[data-alerts-contract-multiselect="true"] span', text: /\+ 1 more/
  end

  test "acknowledge marks alert as acknowledged" do
    alert = alerts(:expiry_warning)
    patch acknowledge_alert_path(alert)

    # With single recipient, alert transitions to acknowledged
    assert_equal "acknowledged", alert.reload.status
  end

  test "acknowledge only marks current user's recipient as read" do
    alert = alerts(:expiry_warning)
    user_two = users(:two)
    org = organizations(:one)
    Membership.find_or_create_by!(user: user_two, organization: org) { |m| m.role = "member" }
    alert.alert_recipients.create!(user: user_two, channel: "email")

    patch acknowledge_alert_path(alert)

    # Current user's recipient is read
    assert_not_nil alert.alert_recipients.find_by(user: users(:one)).read_at
    # Other user's recipient is NOT read
    assert_nil alert.alert_recipients.find_by(user: user_two).read_at
    # Alert remains non-acknowledged since not all recipients read
    assert_not_equal "acknowledged", alert.reload.status
  end

  test "acknowledge creates audit log" do
    alert = alerts(:expiry_warning)
    assert_difference "AuditLog.count", 1 do
      patch acknowledge_alert_path(alert)
    end
    log = AuditLog.last
    assert_equal "alert_acknowledged", log.action
    assert_equal alert.contract, log.contract
  end

  test "acknowledge via turbo stream removes alert card" do
    alert = alerts(:expiry_warning)
    patch acknowledge_alert_path(alert), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "snooze pushes alert forward for current user only" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert, days: 7)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 7.days, recipient.snoozed_until
    # Alert-level trigger_date should not change
    assert_equal alerts(:expiry_warning).trigger_date, alert.reload.trigger_date
  end

  test "snooze creates audit log" do
    alert = alerts(:expiry_warning)
    assert_difference "AuditLog.count", 1 do
      patch snooze_alert_path(alert, days: 7)
    end
    log = AuditLog.last
    assert_equal "alert_snoozed", log.action
    assert_equal alert.contract, log.contract
    assert_match "7 days", log.details
  end

  test "snooze defaults to 7 days" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 7.days, recipient.snoozed_until
  end

  test "snooze with custom days" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert, days: 14)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 14.days, recipient.snoozed_until
  end

  test "snooze clamps excessive days to 90" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert, days: 365)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 90.days, recipient.snoozed_until
  end

  test "snooze via turbo stream removes alert card" do
    alert = alerts(:expiry_warning)
    patch snooze_alert_path(alert, days: 7), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "cannot acknowledge other org's alert" do
    alert = alerts(:other_org_alert)
    patch acknowledge_alert_path(alert)
    assert_redirected_to root_path
    assert_equal "The record you were looking for could not be found.", flash[:alert]
  end

  test "cannot snooze other org's alert" do
    alert = alerts(:other_org_alert)
    patch snooze_alert_path(alert, days: 7)
    assert_redirected_to root_path
    assert_equal "The record you were looking for could not be found.", flash[:alert]
  end

  test "requires authentication" do
    sign_out
    get alerts_path
    assert_response :redirect
  end

  test "notification bell shows unread count" do
    get alerts_path
    assert_select "span.bg-red-500"
  end

  private

  def alert_frame_selector(alert_or_fixture_name)
    alert = alert_or_fixture_name.is_a?(Alert) ? alert_or_fixture_name : alerts(alert_or_fixture_name)
    "turbo-frame#alert_#{alert.id}"
  end

  def create_alert_for_current_user(trigger_date:, alert_type:, message: nil, status: "pending", contract: contracts(:hvac_maintenance))
    alert = Alert.create!(
      organization: organizations(:one),
      contract: contract,
      alert_type: alert_type,
      trigger_date: trigger_date,
      status: status,
      message: message || "#{alert_type} test alert"
    )
    AlertRecipient.create!(alert: alert, user: users(:one), channel: "in_app")
    alert
  end
end
