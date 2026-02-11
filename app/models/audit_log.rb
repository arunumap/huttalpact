class AuditLog < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :contract, optional: true

  ACTIONS = %w[created updated deleted viewed exported alert_sent alert_acknowledged alert_snoozed plan_changed].freeze

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
    else action.titleize
    end
  end
end
