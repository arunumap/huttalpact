require "test_helper"

class CalendarConnectionTest < ActiveSupport::TestCase
  setup do
    @connection = calendar_connections(:google_connection)
  end

  test "valid connection" do
    assert @connection.valid?
  end

  test "requires provider" do
    @connection.provider = nil
    assert_not @connection.valid?
  end

  test "requires valid provider" do
    @connection.provider = "yahoo"
    assert_not @connection.valid?
  end

  test "requires access_token" do
    @connection.access_token = nil
    assert_not @connection.valid?
  end

  test "enforces one connection per user-org-provider" do
    duplicate = @connection.dup
    duplicate.id = nil
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider], "has already been taken"
  end

  test "active scope" do
    active = CalendarConnection.active
    assert active.include?(@connection)
    assert_not active.include?(calendar_connections(:expired_connection))
  end

  test "google? and microsoft?" do
    assert @connection.google?
    assert_not @connection.microsoft?
  end

  test "token_expired?" do
    assert_not @connection.token_expired?
    @connection.token_expires_at = 1.hour.ago
    assert @connection.token_expired?
  end

  test "token_expiring_soon?" do
    assert_not @connection.token_expiring_soon?
    @connection.token_expires_at = 2.minutes.from_now
    assert @connection.token_expiring_soon?
  end

  test "update_tokens!" do
    @connection.update_tokens!(access_token: "new_token", expires_at: 2.hours.from_now)
    assert_equal "new_token", @connection.reload.access_token
    assert_equal "active", @connection.status
  end

  test "mark_error!" do
    @connection.mark_error!("Something failed")
    assert_equal "error", @connection.reload.status
    assert_equal "Something failed", @connection.last_error
  end

  test "mark_revoked!" do
    @connection.mark_revoked!
    assert_equal "revoked", @connection.reload.status
  end

  test "needs_token_refresh scope" do
    @connection.update!(token_expires_at: 2.minutes.from_now)
    assert CalendarConnection.needs_token_refresh.include?(@connection)

    @connection.update!(token_expires_at: 10.minutes.from_now)
    assert_not CalendarConnection.needs_token_refresh.include?(@connection)
  end

  test "destroying connection destroys preference and syncs" do
    assert @connection.calendar_preference.present?
    @connection.destroy!
    assert_equal 0, CalendarPreference.where(calendar_connection_id: @connection.id).count
  end
end
