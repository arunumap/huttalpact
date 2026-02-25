# frozen_string_literal: true

require "test_helper"

class BotScannerBlockerTest < ActiveSupport::TestCase
  setup do
    @app = ->(env) { [ 200, { "content-type" => "text/html" }, [ "OK" ] ] }
    @middleware = BotScannerBlocker.new(@app)
  end

  test "blocks wp-admin paths" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/wp-admin/setup-config.php")
    assert_equal 404, status
  end

  test "blocks wp-login paths" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/wp-login.php")
    assert_equal 404, status
  end

  test "blocks wp-content paths" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/wp-content/uploads/shell.php")
    assert_equal 404, status
  end

  test "blocks phpmyadmin paths" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/phpmyadmin/index.php")
    assert_equal 404, status
  end

  test "blocks .env probe" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/.env")
    assert_equal 404, status
  end

  test "blocks .git probe" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/.git/config")
    assert_equal 404, status
  end

  test "blocks .php extension" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/some/random/page.php")
    assert_equal 404, status
  end

  test "blocks .asp extension" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/default.asp")
    assert_equal 404, status
  end

  test "blocks .sql extension" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/dump.sql")
    assert_equal 404, status
  end

  test "is case-insensitive" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/WP-ADMIN/install.php")
    assert_equal 404, status
  end

  test "returns noindex header for blocked requests" do
    _status, headers, _body = @middleware.call("PATH_INFO" => "/wp-admin/setup-config.php")
    assert_equal "noindex", headers["x-robots-tag"]
  end

  test "passes through legitimate paths" do
    status, _headers, body = @middleware.call("PATH_INFO" => "/contracts")
    assert_equal 200, status
    assert_equal [ "OK" ], body
  end

  test "passes through root path" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/")
    assert_equal 200, status
  end

  test "passes through dashboard path" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/dashboard")
    assert_equal 200, status
  end

  test "passes through API-like paths" do
    status, _headers, _body = @middleware.call("PATH_INFO" => "/alerts")
    assert_equal 200, status
  end

  test "handles nil PATH_INFO gracefully" do
    status, _headers, _body = @middleware.call("PATH_INFO" => nil)
    assert_equal 200, status
  end
end
