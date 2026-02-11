require "test_helper"

class AlertPreferenceTest < ActiveSupport::TestCase
  setup do
    @preference = alert_preferences(:one)
  end

  test "valid alert_preference" do
    assert @preference.valid?
  end

  test "validates days_before_renewal is positive" do
    @preference.days_before_renewal = 0
    assert_not @preference.valid?
  end

  test "validates days_before_renewal is integer" do
    @preference.days_before_renewal = 3.5
    assert_not @preference.valid?
  end

  test "validates days_before_expiry is positive" do
    @preference.days_before_expiry = 0
    assert_not @preference.valid?
  end

  test "validates days_before_expiry is integer" do
    @preference.days_before_expiry = 2.5
    assert_not @preference.valid?
  end

  test "rejects negative days_before_renewal" do
    @preference.days_before_renewal = -1
    assert_not @preference.valid?
  end

  test "rejects negative days_before_expiry" do
    @preference.days_before_expiry = -5
    assert_not @preference.valid?
  end

  test "validates uniqueness of user per organization" do
    dup = AlertPreference.new(
      user: users(:one),
      organization: organizations(:one),
      days_before_renewal: 30,
      days_before_expiry: 14
    )
    assert_not dup.valid?
  end

  test "allows same user in different organizations" do
    pref = AlertPreference.new(
      user: users(:one),
      organization: organizations(:two),
      days_before_renewal: 30,
      days_before_expiry: 14
    )
    assert pref.valid?
  end

  test "belongs to user" do
    assert_equal users(:one), @preference.user
  end

  test "belongs to organization" do
    assert_equal organizations(:one), @preference.organization
  end

  test ".for finds existing preference" do
    found = AlertPreference.for(users(:one), organizations(:one))
    assert found.persisted?
    assert_equal @preference, found
  end

  test ".for initializes new preference for unknown user+org" do
    new_pref = AlertPreference.for(users(:two), organizations(:one))
    assert new_pref.new_record?
  end

  test "default values from schema" do
    pref = AlertPreference.new
    assert_equal true, pref.email_enabled
    assert_equal true, pref.in_app_enabled
    assert_equal 30, pref.days_before_renewal
    assert_equal 14, pref.days_before_expiry
  end
end
