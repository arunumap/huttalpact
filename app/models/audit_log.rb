class AuditLog < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :contract, optional: true

  ACTIONS = %w[
    created
    updated
    deleted
    viewed
    exported
    alert_sent
    alert_acknowledged
    alert_snoozed
    plan_changed
    member_invited
    member_removed
    member_role_changed
    invitation_revoked
    profile_updated
    password_changed
    organization_updated
    extraction_overage
    review_progress_saved
    review_bulk_confirmed
    review_field_confirmed
    review_field_edited
    review_field_marked_not_found
    review_field_marked_not_applicable
    review_completed
    review_alerts_activated
    review_alerts_skipped
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_contract, ->(contract) { where(contract: contract) }
  scope :for_action, ->(action) { where(action: action) }
  scope :for_user, ->(user) { where(user: user) }
  scope :since, ->(date) { where("created_at >= ?", date) if date }

  def action_label
    case action
    when "alert_sent" then "Alert Sent"
    when "alert_acknowledged" then "Alert Acknowledged"
    when "alert_snoozed" then "Alert Snoozed"
    when "plan_changed" then "Plan Changed"
    when "review_progress_saved" then "Saved Review Progress"
    when "review_bulk_confirmed" then "Bulk Confirmed Review Fields"
    when "review_field_confirmed" then "Confirmed Review Field"
    when "review_field_edited" then "Edited Review Field"
    when "review_field_marked_not_found" then "Marked Review Field Not Found"
    when "review_field_marked_not_applicable" then "Marked Review Field Not Applicable"
    when "review_completed" then "Completed Human Review"
    when "review_alerts_activated" then "Activated Approved Alerts"
    when "review_alerts_skipped" then "Skipped Alert Activation"
    else action.titleize
    end
  end
end
