module CalendarProviders
  class MicrosoftAdapter < BaseAdapter
    GRAPH_BASE = "https://graph.microsoft.com/v1.0".freeze
    SCOPE = "Calendars.ReadWrite offline_access User.Read".freeze

    def list_calendars
      ensure_valid_token!
      response = graph_get("/me/calendars")
      (response["value"] || []).filter_map do |cal|
        next unless cal["canEdit"]

        { id: cal["id"], name: cal["name"], primary: cal["isDefaultCalendar"] || false }
      end
    end

    def create_event(calendar_id, candidate, app_host:)
      ensure_valid_token!
      payload = build_graph_event(candidate, app_host)
      response = graph_post("/me/calendars/#{calendar_id}/events", payload)
      response["id"]
    end

    def update_event(calendar_id, remote_event_id, candidate, app_host:)
      ensure_valid_token!
      payload = build_graph_event(candidate, app_host)
      graph_patch("/me/calendars/#{calendar_id}/events/#{remote_event_id}", payload)
      remote_event_id
    rescue Faraday::ResourceNotFound
      create_event(calendar_id, candidate, app_host: app_host)
    end

    def delete_event(calendar_id, remote_event_id)
      ensure_valid_token!
      graph_delete("/me/calendars/#{calendar_id}/events/#{remote_event_id}")
    rescue Faraday::ResourceNotFound
      # Already deleted externally — that's fine
    end

    def refresh_token!
      return unless connection.refresh_token.present?

      client_id = Rails.application.credentials.dig(:microsoft, :client_id)
      client_secret = Rails.application.credentials.dig(:microsoft, :client_secret)
      if client_id.blank? || client_secret.blank?
        raise MissingCredentialsError, "Microsoft Calendar credentials are missing. Configure microsoft.client_id and microsoft.client_secret."
      end

      client = OAuth2::Client.new(
        client_id,
        client_secret,
        site: "https://login.microsoftonline.com",
        token_url: "/common/oauth2/v2.0/token"
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

    def graph_connection
      @graph_connection ||= Faraday.new(url: GRAPH_BASE) do |f|
        f.request :json
        f.response :json
        f.response :raise_error
        f.headers["Authorization"] = "Bearer #{connection.access_token}"
        f.headers["Content-Type"] = "application/json"
      end
    end

    def graph_get(path)
      graph_connection.get(path).body
    end

    def graph_post(path, body)
      graph_connection.post(path, body).body
    end

    def graph_patch(path, body)
      graph_connection.patch(path, body).body
    end

    def graph_delete(path)
      graph_connection.delete(path)
    end

    def build_graph_event(candidate, app_host)
      event = {
        subject: candidate.title,
        body: {
          contentType: "text",
          content: "#{candidate.description}\n\nView in Sagebadger: #{app_host}#{candidate.deep_link_path}"
        },
        start: { dateTime: "#{candidate.date}T00:00:00", timeZone: "UTC" },
        end: { dateTime: "#{candidate.date}T23:59:59", timeZone: "UTC" },
        isAllDay: true,
        isReminderOn: true,
        reminderMinutesBeforeStart: [ (candidate.reminder_days || 1) * 24 * 60, 20_160 ].min
      }

      if candidate.recurrence_rule.present?
        event[:recurrence] = build_graph_recurrence(candidate)
      end

      event
    end

    def build_graph_recurrence(candidate)
      case candidate.recurrence_rule
      when "RRULE:FREQ=MONTHLY"
        {
          pattern: { type: "absoluteMonthly", interval: 1, dayOfMonth: candidate.date.day },
          range: { type: "noEnd", startDate: candidate.date.to_s }
        }
      when "RRULE:FREQ=MONTHLY;INTERVAL=3"
        {
          pattern: { type: "absoluteMonthly", interval: 3, dayOfMonth: candidate.date.day },
          range: { type: "noEnd", startDate: candidate.date.to_s }
        }
      when "RRULE:FREQ=YEARLY"
        {
          pattern: { type: "absoluteYearly", interval: 1, dayOfMonth: candidate.date.day, month: candidate.date.month },
          range: { type: "noEnd", startDate: candidate.date.to_s }
        }
      end
    end
  end
end
