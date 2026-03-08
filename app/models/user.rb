class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :alert_recipients, dependent: :destroy
  has_many :alerts, through: :alert_recipients
  has_many :alert_preferences, dependent: :destroy
  has_many :audit_logs, dependent: :nullify
  has_many :bulk_delete_operations, dependent: :destroy
  has_many :contract_review_field_events, dependent: :nullify
  has_many :reviewed_contract_review_fields, class_name: "ContractReviewField", foreign_key: :reviewed_by_id, dependent: :nullify
  has_many :resolved_contract_review_conflicts, class_name: "ContractReviewConflict", foreign_key: :resolved_by_id, dependent: :nullify
  has_many :extraction_feedbacks, dependent: :destroy
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id, dependent: :nullify
  has_many :uploaded_contracts, class_name: "Contract", foreign_key: :uploaded_by_id, dependent: :nullify

  attr_accessor :terms_accepted

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  validates :first_name, length: { maximum: 100 }, allow_nil: true
  validates :last_name, length: { maximum: 100 }, allow_nil: true
  validate :terms_must_be_accepted, on: :create

  scope :without_organizations, -> { left_outer_joins(:memberships).where(memberships: { id: nil }).distinct }

  def membership_in(organization)
    memberships.find_by(organization: organization)
  end

  def without_organizations?
    memberships.none?
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence || email_address
  end

  def initials
    if first_name.present?
      "#{first_name[0]}#{last_name&.[](0)}".upcase
    else
      email_address[0..1].upcase
    end
  end

  private

  def terms_must_be_accepted
    errors.add(:terms_accepted, "You must accept the Terms of Use and Privacy Policy") unless terms_accepted == "1"
  end
end
