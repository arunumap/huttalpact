class ContractReviewFieldEvent < ApplicationRecord
  acts_as_tenant :organization

  ACTIONS = %w[
    extracted
    confirmed
    edited
    marked_not_found
    marked_not_applicable
    reopened
    conflict_opened
    conflict_resolved
    bulk_confirmed
    recalculated
  ].freeze

  belongs_to :contract_review
  belongs_to :contract_review_field
  belongs_to :contract
  belongs_to :organization
  belongs_to :user, optional: true

  before_validation :assign_parent_references

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action: action) }

  validate :field_matches_review
  validate :field_matches_contract
  validate :field_matches_organization

  private

  def assign_parent_references
    self.contract_review ||= contract_review_field&.contract_review
    self.contract ||= contract_review_field&.contract || contract_review&.contract
    self.organization ||= contract_review_field&.organization || contract_review&.organization || contract&.organization
  end

  def field_matches_review
    return if contract_review_field.blank? || contract_review.blank?
    return if contract_review_field.contract_review_id == contract_review_id

    errors.add(:contract_review, "must match the review field review")
  end

  def field_matches_contract
    return if contract_review_field.blank? || contract.blank?
    return if contract_review_field.contract_id == contract_id

    errors.add(:contract, "must match the review field contract")
  end

  def field_matches_organization
    return if contract_review_field.blank? || organization.blank?
    return if contract_review_field.organization_id == organization_id

    errors.add(:organization, "must match the review field organization")
  end
end
