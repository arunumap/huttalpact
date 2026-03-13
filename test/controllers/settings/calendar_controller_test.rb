require "test_helper"

class Settings::CalendarControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "should get show when not connected" do
    # Remove any existing preferences and connections for user one
    CalendarPreference.where(user: users(:one), organization: organizations(:one)).delete_all
    CalendarConnection.where(user: users(:one), organization: organizations(:one), provider: "google").delete_all

    get settings_calendar_path
    assert_response :success
    assert_match "Connect a Calendar", response.body
  end

  test "should get show when connected" do
    get settings_calendar_path
    assert_response :success
    assert_match "Calendar Connected", response.body
  end

  test "disconnect removes connection" do
    connection = calendar_connections(:google_connection)
    assert CalendarConnection.exists?(connection.id)

    delete disconnect_settings_calendar_path
    assert_redirected_to settings_calendar_path
    assert_not CalendarConnection.exists?(connection.id)
  end

  test "update preferences enqueues sync" do
    connection = calendar_connections(:google_connection)

    assert_enqueued_with(job: SyncCalendarEventsJob, args: [ connection.id ]) do
      patch settings_calendar_path, params: {
        calendar_preference: {
          sync_enabled: true,
          enabled_categories: [ "expiry_warning", "renewal_upcoming" ]
        }
      }
    end

    assert_redirected_to settings_calendar_path
  end

  test "requires authentication" do
    sign_out
    get settings_calendar_path
    assert_response :redirect
  end
end
