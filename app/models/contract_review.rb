class ContractReview < ApplicationRecord
  acts_as_tenant :organization

  STATUSES = %w[open completed superseded].freeze
  REVIEW_TRIGGERS = %w[initial_extraction addendum_upload manual_backfill].freeze

  belongs_to :organization
  belongs_to :contract
  belongs_to :ai_usage_log, optional: true

  has_many :contract_review_fields, dependent: :destroy
  has_many :contract_review_conflicts, dependent: :destroy
  has_many :contract_review_field_events, dependent: :destroy

  before_validation :assign_organization_from_contract

  validates :status, inclusion: { in: STATUSES }
  validates :review_trigger, inclusion: { in: REVIEW_TRIGGERS }
  validates :contract_id, uniqueness: {
    conditions: -> { where(status: "open") },
    message: "already has an open review"
  }, if: :open?

  scope :open, -> { where(status: "open") }
  scope :completed, -> { where(status: "completed") }
  scope :superseded, -> { where(status: "superseded") }
  scope :recent, -> { order(created_at: :desc) }

  validate :organization_matches_contract
  validate :ai_usage_log_matches_contract

  def open?
    status == "open"
  end

  def completed?
    status == "completed"
  end

  def superseded?
    status == "superseded"
  end

  def refresh_summary!
    return unless persisted?

    fields_scope = ContractReviewField.unscoped.where(contract_review_id: id)
    conflicts_scope = ContractReviewConflict.unscoped.where(contract_review_id: id)

    update_columns(
      total_fields_count: fields_scope.count,
      pending_fields_count: fields_scope.where(readiness_bucket: "pending").count,
      looks_good_fields_count: fields_scope.where(readiness_bucket: "looks_good").count,
      needs_review_fields_count: fields_scope.where(readiness_bucket: "needs_review").count,
      blocked_fields_count: fields_scope.where(readiness_bucket: "blocked").count,
      open_conflicts_count: conflicts_scope.where(status: "open").count,
      updated_at: Time.current
    )
  end

  def standard_priority_open_items_summary
    fields_scope = ContractReviewField.unscoped.where(contract_review_id: id, readiness_bucket: "needs_review", gates_activation: false)

    {
      count: fields_scope.count,
      field_keys: fields_scope.distinct.order(:field_key).pluck(:field_key)
    }
  end

  def pending_follow_through_fields
    ContractReviewField.unscoped.where(contract_review_id: id, readiness_bucket: "needs_review", gates_activation: false, review_status: "pending")
  end

  def resolved_follow_through_fields
    return ContractReviewField.none if completed_at.blank?

    ContractReviewField.unscoped
      .where(contract_review_id: id, readiness_bucket: "needs_review", gates_activation: false)
      .where.not(review_status: "pending")
      .where("reviewed_at > ?", completed_at)
  end

  def average_follow_through_resolution_seconds
    return nil if completed_at.blank?

    durations = resolved_follow_through_fields.pluck(:reviewed_at).filter_map do |reviewed_at|
      next if reviewed_at.blank?

      reviewed_at - completed_at
    end

    return nil if durations.empty?

    durations.sum / durations.size.to_f
  end

  def follow_through_summary
    average_seconds = average_follow_through_resolution_seconds

    {
      pending_count: pending_follow_through_fields.count,
      resolved_count: resolved_follow_through_fields.count,
      average_resolution_hours: average_seconds ? (average_seconds / 1.hour).round(1) : nil
    }
  end

  private

  def assign_organization_from_contract
    self.organization ||= contract&.organization
  end

  def organization_matches_contract
    return if contract.blank? || organization.blank?
    return if contract.organization_id == organization_id

    errors.add(:organization, "must match the contract organization")
  end

  def ai_usage_log_matches_contract
    return if ai_usage_log.blank?

    if ai_usage_log.contract_id != contract_id
      errors.add(:ai_usage_log, "must belong to the same contract")
    end

    if organization_id.present? && ai_usage_log.organization_id != organization_id
      errors.add(:ai_usage_log, "must belong to the same organization")
    end
  end
end
