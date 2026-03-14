require "google/apis/calendar_v3"

module CalendarProviders
  class GoogleAdapter < BaseAdapter
    SCOPE = [
      "https://www.googleapis.com/auth/calendar.events",
      "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    ].join(" ").freeze

    def list_calendars
      ensure_valid_token!
      response = service.list_calendar_lists
      response.items.filter_map do |cal|
        next unless cal.access_role.in?(%w[writer owner])

        { id: cal.id, name: cal.summary, primary: cal.primary || false }
      end
    rescue Google::Apis::AuthorizationError => e
      connection.mark_error!("Authorization failed: #{e.message}")
      raise
    end

    def create_event(calendar_id, candidate, app_host:)
      ensure_valid_token!
      event = build_google_event(candidate, app_host)
      result = service.insert_event(calendar_id, event)
      result.id
    rescue Google::Apis::AuthorizationError => e
      connection.mark_error!("Authorization failed: #{e.message}")
      raise
    end

    def update_event(calendar_id, remote_event_id, candidate, app_host:)
      ensure_valid_token!
      event = build_google_event(candidate, app_host)
      service.update_event(calendar_id, remote_event_id, event)
      remote_event_id
    rescue Google::Apis::ClientError => e
      raise unless e.message.include?("notFound")
      # Event was deleted externally; create a new one
      create_event(calendar_id, candidate, app_host: app_host)
    rescue Google::Apis::AuthorizationError => e
      connection.mark_error!("Authorization failed: #{e.message}")
      raise
    end

    def delete_event(calendar_id, remote_event_id)
      ensure_valid_token!
      service.delete_event(calendar_id, remote_event_id)
    rescue Google::Apis::ClientError => e
      raise unless e.message.include?("notFound")
      # Already deleted externally — that's fine
    rescue Google::Apis::AuthorizationError => e
      connection.mark_error!("Authorization failed: #{e.message}")
      raise
    end

    def refresh_token!
      return unless connection.refresh_token.present?

      client_id = Rails.application.credentials.dig(:google, :client_id)
      client_secret = Rails.application.credentials.dig(:google, :client_secret)
      if client_id.blank? || client_secret.blank?
        raise MissingCredentialsError, "Google Calendar credentials are missing. Configure google.client_id and google.client_secret."
      end

      client = OAuth2::Client.new(
        client_id,
        client_secret,
        site: "https://accounts.google.com",
        token_url: "https://oauth2.googleapis.com/token"
      )

      token = OAuth2::AccessToken.new(client, connection.access_token,
        refresh_token: connection.refresh_token)
      new_token = token.refresh!

      connection.update_tokens!(
        access_token: new_token.token,
        refresh_token: new_token.refresh_token || connection.refresh_token,
        expires_at: Time.at(new_token.expires_at)
      )
    end

    private

    def service
      @service ||= begin
        svc = Google::Apis::CalendarV3::CalendarService.new
        svc.authorization = google_authorization
        svc
      end
    end

    def google_authorization
      token = connection.access_token
      # The google-apis-calendar_v3 gem accepts an access token string via a
      # simple object that responds to #apply! and #on_refresh
      Struct.new(:token).new(token).tap do |auth|
        def auth.apply!(headers)
          headers["Authorization"] = "Bearer #{token}"
        end
      end
    end

    def build_google_event(candidate, app_host)
      event = Google::Apis::CalendarV3::Event.new(
        summary: candidate.title,
        description: "#{candidate.description}\n\nView in Sagebadger: #{app_host}#{candidate.deep_link_path}",
        start: Google::Apis::CalendarV3::EventDateTime.new(date: candidate.date.to_s),
        end: Google::Apis::CalendarV3::EventDateTime.new(date: candidate.date.to_s),
        reminders: Google::Apis::CalendarV3::Event::Reminders.new(
          use_default: false,
          overrides: [
            Google::Apis::CalendarV3::EventReminder.new(
              reminder_method: "popup",
              minutes: [ (candidate.reminder_days || 1) * 24 * 60, 40_320 ].min # max 4 weeks
            )
          ]
        ),
        source: Google::Apis::CalendarV3::Event::Source.new(
          title: "Sagebadger",
          url: "#{app_host}#{candidate.deep_link_path}"
        )
      )

      if candidate.recurrence_rule.present?
        event.recurrence = [ candidate.recurrence_rule ]
      end

      event
    end
  end
end
