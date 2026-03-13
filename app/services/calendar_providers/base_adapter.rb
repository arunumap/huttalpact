# Base adapter defining the interface all calendar providers must implement.
module CalendarProviders
  class BaseAdapter
    class MissingCredentialsError < StandardError; end

    attr_reader :connection

    def initialize(connection)
      @connection = connection
    end

    def list_calendars
      raise NotImplementedError
    end

    def create_event(calendar_id, event_payload)
      raise NotImplementedError
    end

    def update_event(calendar_id, remote_event_id, event_payload)
      raise NotImplementedError
    end

    def delete_event(calendar_id, remote_event_id)
      raise NotImplementedError
    end

    def refresh_token!
      raise NotImplementedError
    end

    protected

    def ensure_valid_token!
      refresh_token! if connection.token_expiring_soon?
    end

    def build_event_payload(candidate, app_host)
      {
        title: candidate.title,
        date: candidate.date,
        description: candidate.description,
        deep_link: "#{app_host}#{candidate.deep_link_path}",
        recurrence_rule: candidate.recurrence_rule,
        reminder_minutes: (candidate.reminder_days || 1) * 24 * 60
      }
    end
  end
end
