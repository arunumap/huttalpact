# frozen_string_literal: true

# Rack middleware that silently returns 404 for known bot/scanner probe paths.
# These are automated requests looking for WordPress, phpMyAdmin, and other
# common CMS/admin panels that don't exist on this app. Without this middleware,
# each probe generates a noisy ActionController::RoutingError in the logs.
class BotScannerBlocker
  # Common paths probed by vulnerability scanners and bots.
  # Matches any request path starting with these prefixes.
  BLOCKED_PREFIXES = %w[
    /wp-admin
    /wp-login
    /wp-content
    /wp-includes
    /wp-json
    /wordpress
    /xmlrpc.php
    /phpmyadmin
    /pma
    /myadmin
    /mysql
    /dbadmin
    /admin/config
    /.env
    /.git
    /.aws
    /.well-known/security.txt
    /cgi-bin
    /vendor/phpunit
    /solr
    /actuator
    /api/v1/../../
    /telescope/requests
    /debug
    /server-status
    /server-info
    /config.json
    /credentials
    /backup
    /dump
  ].freeze

  # File extensions that are never served by this app.
  BLOCKED_EXTENSIONS = /\.(php|asp|aspx|jsp|cgi|sql|bak|old|orig|swp)$/i

  RESPONSE_BODY = [ "Not Found" ].freeze
  RESPONSE_HEADERS = { "content-type" => "text/plain", "x-robots-tag" => "noindex" }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s

    if blocked?(path)
      [ 404, RESPONSE_HEADERS, RESPONSE_BODY ]
    else
      @app.call(env)
    end
  end

  private

  def blocked?(path)
    downcased = path.downcase
    BLOCKED_PREFIXES.any? { |prefix| downcased.start_with?(prefix) } ||
      BLOCKED_EXTENSIONS.match?(downcased)
  end
end
