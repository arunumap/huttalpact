class Settings::CalendarController < ApplicationController
  rescue_from CalendarProviders::BaseAdapter::MissingCredentialsError, with: :handle_missing_credentials

  def show
    @connection = current_calendar_connection
    @preference = @connection&.calendar_preference
    @calendars = fetch_calendars if @connection&.active?
  end

  def connect_google
    state = SecureRandom.hex(24)
    session[:calendar_oauth_state] = state

    client = google_oauth_client
    redirect_to client.auth_code.authorize_url(
      redirect_uri: google_callback_settings_calendar_url,
      scope: CalendarProviders::GoogleAdapter::SCOPE,
      access_type: "offline",
      prompt: "consent",
      state: state
    ), allow_other_host: true
  end

  def connect_microsoft
    state = SecureRandom.hex(24)
    session[:calendar_oauth_state] = state

    client = microsoft_oauth_client
    redirect_to client.auth_code.authorize_url(
      redirect_uri: microsoft_callback_settings_calendar_url,
      scope: CalendarProviders::MicrosoftAdapter::SCOPE,
      state: state
    ), allow_other_host: true
  end

  def google_callback
    verify_oauth_state!

    client = google_oauth_client
    token = client.auth_code.get_token(
      params[:code],
      redirect_uri: google_callback_settings_calendar_url
    )

    upsert_connection!(
      provider: "google",
      access_token: token.token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
      provider_email: fetch_google_email(token.token)
    )

    redirect_to settings_calendar_path, notice: "Google Calendar connected successfully."
  rescue OAuth2::Error, StandardError => e
    redirect_to settings_calendar_path, alert: "Failed to connect Google Calendar: #{e.message}"
  end

  def microsoft_callback
    verify_oauth_state!

    client = microsoft_oauth_client
    token = client.auth_code.get_token(
      params[:code],
      redirect_uri: microsoft_callback_settings_calendar_url
    )

    upsert_connection!(
      provider: "microsoft",
      access_token: token.token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
      provider_email: fetch_microsoft_email(token.token)
    )

    redirect_to settings_calendar_path, notice: "Microsoft Outlook connected successfully."
  rescue OAuth2::Error, StandardError => e
    redirect_to settings_calendar_path, alert: "Failed to connect Microsoft Outlook: #{e.message}"
  end

  def select_calendar
    connection = current_calendar_connection
    unless connection&.active?
      redirect_to settings_calendar_path, alert: "Please connect a calendar provider first."
      return
    end

    preference = connection.calendar_preference || connection.build_calendar_preference(
      user: Current.user,
      organization: Current.organization
    )

    preference.assign_attributes(calendar_preference_params)

    if preference.save
      SyncCalendarEventsJob.perform_later(connection.id)
      redirect_to settings_calendar_path, notice: "Calendar preferences saved. Sync starting..."
    else
      redirect_to settings_calendar_path, alert: "Failed to save preferences: #{preference.errors.full_messages.join(', ')}"
    end
  end

  def update
    connection = current_calendar_connection
    preference = connection&.calendar_preference

    unless preference
      redirect_to settings_calendar_path, alert: "No calendar configured."
      return
    end

    preference.assign_attributes(calendar_update_params)

    if preference.save
      SyncCalendarEventsJob.perform_later(connection.id)
      redirect_to settings_calendar_path, notice: "Calendar preferences updated."
    else
      redirect_to settings_calendar_path, alert: "Failed to update: #{preference.errors.full_messages.join(', ')}"
    end
  end

  def disconnect
    connection = current_calendar_connection
    if connection
      provider_label = connection.provider.titleize
      provider_email = connection.provider_email
      remote_cleanup_errors = remove_remote_events(connection)
      connection.calendar_event_syncs.update_all(sync_status: "deleted")
      connection.destroy!

      AuditLog.create(
        organization: Current.organization,
        user: Current.user,
        action: "calendar_disconnected",
        details: "Disconnected #{provider_label} Calendar (#{provider_email})"
      )

      notice_message = if remote_cleanup_errors.positive?
        "Calendar disconnected. Some remote events could not be deleted."
      else
        "Calendar disconnected."
      end
      redirect_to settings_calendar_path, notice: notice_message
    else
      redirect_to settings_calendar_path
    end
  end

  private

  def current_calendar_connection
    Current.user.calendar_connections.find_by(organization: Current.organization)
  end

  def verify_oauth_state!
    expected = session.delete(:calendar_oauth_state)
    if expected.blank? || params[:state] != expected
      raise "Invalid OAuth state parameter"
    end
  end

  def upsert_connection!(provider:, access_token:, refresh_token:, expires_at:, provider_email:)
    connection = Current.user.calendar_connections.find_or_initialize_by(
      organization: Current.organization,
      provider: provider
    )

    connection.assign_attributes(
      access_token: access_token,
      refresh_token: refresh_token || connection.refresh_token,
      token_expires_at: expires_at,
      provider_email: provider_email,
      status: "active",
      last_error: nil
    )

    connection.save!

    AuditLog.create(
      organization: Current.organization,
      user: Current.user,
      action: "calendar_connected",
      details: "Connected #{provider.titleize} Calendar (#{provider_email})"
    )
  end

  def fetch_google_email(access_token)
    conn = Faraday.new(url: "https://www.googleapis.com") { |f| f.response :json }
    response = conn.get("/oauth2/v2/userinfo") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end
    response.body["email"]
  rescue => e
    Rails.logger.warn("Failed to fetch Google email: #{e.message}")
    nil
  end

  def fetch_microsoft_email(access_token)
    conn = Faraday.new(url: "https://graph.microsoft.com") { |f| f.response :json }
    response = conn.get("/v1.0/me") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end
    response.body["mail"] || response.body["userPrincipalName"]
  rescue => e
    Rails.logger.warn("Failed to fetch Microsoft email: #{e.message}")
    nil
  end

  def fetch_calendars
    connection = current_calendar_connection
    adapter = provider_adapter(connection)
    adapter&.list_calendars || []
  rescue => e
    Rails.logger.error("Failed to list calendars: #{e.message}")
    []
  end

  def google_oauth_client
    client_id = credential!(:google, :client_id)
    client_secret = credential!(:google, :client_secret)

    OAuth2::Client.new(
      client_id,
      client_secret,
      site: "https://accounts.google.com",
      authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token"
    )
  end

  def microsoft_oauth_client
    client_id = credential!(:microsoft, :client_id)
    client_secret = credential!(:microsoft, :client_secret)

    OAuth2::Client.new(
      client_id,
      client_secret,
      site: "https://login.microsoftonline.com",
      authorize_url: "/common/oauth2/v2.0/authorize",
      token_url: "/common/oauth2/v2.0/token"
    )
  end

  def calendar_preference_params
    params.require(:calendar_preference).permit(:remote_calendar_id, :remote_calendar_name, :sync_enabled, enabled_categories: [])
  end

  def calendar_update_params
    params.require(:calendar_preference).permit(:sync_enabled, enabled_categories: [])
  end

  def provider_adapter(connection)
    return nil unless connection

    case connection.provider
    when "google" then CalendarProviders::GoogleAdapter.new(connection)
    when "microsoft" then CalendarProviders::MicrosoftAdapter.new(connection)
    end
  end

  def remove_remote_events(connection)
    preference = connection.calendar_preference
    return 0 unless preference&.remote_calendar_id.present?

    adapter = provider_adapter(connection)
    return 0 unless adapter

    failed_deletes = 0
    connection.calendar_event_syncs.where.not(sync_status: "deleted").where.not(remote_event_id: nil).find_each do |sync_record|
      adapter.delete_event(preference.remote_calendar_id, sync_record.remote_event_id)
    rescue => e
      failed_deletes += 1
      Rails.logger.error("Failed to delete remote event #{sync_record.id} during disconnect: #{e.message}")
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    failed_deletes
  end

  def credential!(provider, key)
    value = Rails.application.credentials.dig(provider, key)
    return value if value.present?

    raise CalendarProviders::BaseAdapter::MissingCredentialsError,
      "#{provider.to_s.titleize} Calendar is not configured. Missing #{provider}.#{key}."
  end

  def handle_missing_credentials(error)
    redirect_to settings_calendar_path, alert: error.message
  end
end
