require "test_helper"

class CalendarPreferenceTest < ActiveSupport::TestCase
  setup do
    @preference = calendar_preferences(:google_preference)
  end

  test "valid preference" do
    assert @preference.valid?
  end

  test "requires remote_calendar_id" do
    @preference.remote_calendar_id = nil
    assert_not @preference.valid?
  end

  test "enforces one preference per connection" do
    duplicate = @preference.dup
    duplicate.id = nil
    assert_not duplicate.valid?
  end

  test "sync_enabled? checks both flag and connection status" do
    assert @preference.sync_enabled?

    @preference.sync_enabled = false
    assert_not @preference.sync_enabled?

    @preference.sync_enabled = true
    @preference.calendar_connection.status = "expired"
    assert_not @preference.sync_enabled?
  end

  test "effective_categories returns all when empty" do
    @preference.enabled_categories = []
    assert_equal CalendarPreference::ALL_CATEGORIES, @preference.effective_categories
  end

  test "effective_categories filters to valid categories" do
    @preference.enabled_categories = [ "expiry_warning", "renewal_upcoming" ]
    assert_equal [ "expiry_warning", "renewal_upcoming" ], @preference.effective_categories
  end

  test "rejects invalid categories" do
    @preference.enabled_categories = [ "expiry_warning", "invalid_type" ]
    assert_not @preference.valid?
    assert_includes @preference.errors[:enabled_categories].first, "invalid_type"
  end

  test "strips blank categories before validation" do
    @preference.enabled_categories = [ "", "expiry_warning", "  ", nil ]
    assert @preference.valid?
    assert_equal [ "expiry_warning" ], @preference.enabled_categories
  end

  test "category_enabled?" do
    @preference.enabled_categories = [ "expiry_warning" ]
    assert @preference.category_enabled?("expiry_warning")
    assert_not @preference.category_enabled?("renewal_upcoming")
  end
end
