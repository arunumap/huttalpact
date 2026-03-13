# Orchestrates one-way sync from Sagebadger to a user's connected calendar.
# Compares projected event candidates against existing CalendarEventSync records,
# then creates, updates, or deletes remote events as needed.
class CalendarSyncService
  def initialize(calendar_connection)
    @connection = calendar_connection
    @preference = calendar_connection.calendar_preference
    @user = calendar_connection.user
    @organization = calendar_connection.organization
  end

  def sync!
    return unless @preference&.sync_enabled?
    return unless @connection.active?

    candidates = project_candidates
    existing_syncs = @connection.calendar_event_syncs.where.not(sync_status: "deleted").index_by { |s|
      [ s.source_type, s.source_id, s.event_category ]
    }

    candidate_keys = Set.new

    candidates.each do |candidate|
      key = [ candidate.source_type, candidate.source_id, candidate.event_category ]
      candidate_keys << key

      sync_record = existing_syncs[key]
      if sync_record
        update_if_changed(sync_record, candidate)
      else
        create_remote_event(candidate)
      end
    end

    # Delete events that no longer have a matching candidate
    stale_syncs = existing_syncs.reject { |key, _| candidate_keys.include?(key) }
    stale_syncs.each_value { |sync_record| delete_remote_event(sync_record) }

    @connection.update!(last_synced_at: Time.current)
  rescue => e
    @connection.mark_error!(e.message)
    Rails.logger.error("Calendar sync failed for connection #{@connection.id}: #{e.message}")
    Sentry.capture_exception(e) if Sentry.initialized?
  end

  # Sync a single contract's events (used when a contract changes)
  def sync_contract!(contract)
    return unless @preference&.sync_enabled?
    return unless @connection.active?

    candidates = project_candidates.select { |c|
      c.source_type == "Contract" && c.source_id == contract.id ||
        related_source?(c, contract)
    }

    existing_syncs = @connection.calendar_event_syncs
      .where(source_type: related_source_types, source_id: related_source_ids(contract))
      .where.not(sync_status: "deleted")
      .index_by { |s| [ s.source_type, s.source_id, s.event_category ] }

    candidate_keys = Set.new

    candidates.each do |candidate|
      key = [ candidate.source_type, candidate.source_id, candidate.event_category ]
      candidate_keys << key

      sync_record = existing_syncs[key]
      if sync_record
        update_if_changed(sync_record, candidate)
      else
        create_remote_event(candidate)
      end
    end

    stale_syncs = existing_syncs.reject { |key, _| candidate_keys.include?(key) }
    stale_syncs.each_value { |sync_record| delete_remote_event(sync_record) }
  rescue => e
    Rails.logger.error("Calendar sync for contract #{contract.id} failed: #{e.message}")
    Sentry.capture_exception(e) if Sentry.initialized?
  end

  private

  def project_candidates
    @candidates ||= CalendarEventProjector.new(
      organization: @organization,
      user: @user
    ).project(categories: @preference.effective_categories)
  end

  def adapter
    @adapter ||= case @connection.provider
    when "google" then CalendarProviders::GoogleAdapter.new(@connection)
    when "microsoft" then CalendarProviders::MicrosoftAdapter.new(@connection)
    else raise "Unknown calendar provider: #{@connection.provider}"
    end
  end

  def app_host
    @app_host ||= Rails.application.routes.default_url_options[:host] || "https://app.sagebadger.com"
  end

  def calendar_id
    @preference.remote_calendar_id
  end

  def create_remote_event(candidate)
    sync_record = reserve_sync_record(candidate)

    if sync_record.remote_event_id.present?
      update_if_changed(sync_record, candidate)
      return
    end

    remote_id = adapter.create_event(calendar_id, candidate, app_host: app_host)
    sync_record.mark_synced!(remote_event_id: remote_id, fingerprint: candidate.fingerprint)
  rescue => e
    record_sync_failure(candidate, e, sync_record: sync_record)
  end

  def update_if_changed(sync_record, candidate)
    if sync_record.remote_event_id.blank?
      remote_id = adapter.create_event(calendar_id, candidate, app_host: app_host)
      sync_record.mark_synced!(remote_event_id: remote_id, fingerprint: candidate.fingerprint)
      return
    end

    return unless sync_record.needs_update?(candidate.fingerprint)

    remote_id = adapter.update_event(calendar_id, sync_record.remote_event_id, candidate, app_host: app_host)
    sync_record.mark_synced!(remote_event_id: remote_id, fingerprint: candidate.fingerprint)
  rescue => e
    sync_record.mark_failed!(e.message)
  end

  def delete_remote_event(sync_record)
    adapter.delete_event(calendar_id, sync_record.remote_event_id) if sync_record.remote_event_id.present?
    sync_record.mark_deleted!
  rescue => e
    sync_record.mark_failed!(e.message)
  end

  def related_source?(candidate, contract)
    case candidate.source_type
    when "LeaseOption"
      contract.lease_options.exists?(candidate.source_id)
    when "RentEscalation"
      contract.rent_escalations.exists?(candidate.source_id)
    when "LeaseDetail"
      contract.lease_detail&.id == candidate.source_id
    when "LeaseMilestone"
      contract.lease_milestones.exists?(candidate.source_id)
    else
      false
    end
  end

  def related_source_types
    %w[Contract LeaseOption RentEscalation LeaseDetail LeaseMilestone]
  end

  def related_source_ids(contract)
    ids = [ contract.id ]
    ids.concat(contract.lease_options.pluck(:id))
    ids.concat(contract.rent_escalations.pluck(:id))
    ids << contract.lease_detail.id if contract.lease_detail
    ids.concat(contract.lease_milestones.pluck(:id))
    ids
  end

  def reserve_sync_record(candidate)
    attributes = sync_lookup_attributes(candidate)

    @connection.with_lock do
      sync_record = @connection.calendar_event_syncs.lock("FOR UPDATE").find_or_initialize_by(attributes)
      return sync_record unless sync_record.new_record?

      sync_record.assign_attributes(
        organization: @organization,
        remote_calendar_id: calendar_id,
        sync_status: "pending"
      )
      sync_record.save!
      sync_record
    end
  rescue ActiveRecord::RecordNotUnique
    @connection.calendar_event_syncs.find_by!(attributes)
  end

  def record_sync_failure(candidate, error, sync_record: nil)
    failed_record = sync_record || reserve_sync_record(candidate)
    failed_record.mark_failed!(error.message)
  rescue => mark_error
    Rails.logger.error("Unable to persist calendar sync failure for connection #{@connection.id}: #{mark_error.message}")
    Sentry.capture_exception(mark_error) if Sentry.initialized?
  end

  def sync_lookup_attributes(candidate)
    {
      source_type: candidate.source_type,
      source_id: candidate.source_id,
      event_category: candidate.event_category
    }
  end
end
