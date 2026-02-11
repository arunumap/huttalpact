require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "validates email presence" do
    user = User.new(email_address: nil, password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "can't be blank"
  end

  test "validates email uniqueness" do
    existing = users(:one)
    user = User.new(email_address: existing.email_address, password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "has already been taken"
  end

  test "validates email format" do
    user = User.new(email_address: "not-an-email", password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "is invalid"
  end

  test "full_name returns first + last name" do
    user = User.new(first_name: "Alice", last_name: "Johnson")
    assert_equal "Alice Johnson", user.full_name
  end

  test "full_name returns first name only when no last name" do
    user = User.new(first_name: "Alice", email_address: "alice@example.com")
    assert_equal "Alice", user.full_name
  end

  test "full_name falls back to email" do
    user = User.new(email_address: "alice@example.com")
    assert_equal "alice@example.com", user.full_name
  end

  test "initials from name" do
    user = User.new(first_name: "Alice", last_name: "Johnson")
    assert_equal "AJ", user.initials
  end

  test "initials from email when no name" do
    user = User.new(email_address: "alice@example.com")
    assert_equal "AL", user.initials
  end

  test "has many organizations through memberships" do
    user = users(:one)
    assert_includes user.organizations, organizations(:one)
  end

  # Password length validation tests
  test "rejects password shorter than 8 characters" do
    user = User.new(email_address: "short@example.com", password: "abc", password_confirmation: "abc")
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "accepts password of exactly 8 characters" do
    user = User.new(email_address: "exact8@example.com", password: "12345678", password_confirmation: "12345678")
    assert user.valid?
  end

  test "rejects password longer than 72 characters" do
    long_pw = "a" * 73
    user = User.new(email_address: "long@example.com", password: long_pw, password_confirmation: long_pw)
    assert_not user.valid?
    assert_includes user.errors[:password], "is too long (maximum is 72 characters)"
  end

  # Name length validation tests
  test "rejects first_name longer than 100 characters" do
    user = User.new(email_address: "toolong@example.com", password: "password123", first_name: "a" * 101)
    assert_not user.valid?
    assert_includes user.errors[:first_name], "is too long (maximum is 100 characters)"
  end

  test "rejects last_name longer than 100 characters" do
    user = User.new(email_address: "toolong2@example.com", password: "password123", last_name: "a" * 101)
    assert_not user.valid?
    assert_includes user.errors[:last_name], "is too long (maximum is 100 characters)"
  end

  test "accepts names within 100 characters" do
    user = User.new(email_address: "okname@example.com", password: "password123", first_name: "a" * 100, last_name: "b" * 100)
    assert user.valid?
  end
end
