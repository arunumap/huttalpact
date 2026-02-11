class AlertRecipient < ApplicationRecord
  belongs_to :alert
  belongs_to :user

  CHANNELS = %w[email in_app].freeze

  validates :channel, inclusion: { in: CHANNELS }
  validates :user_id, uniqueness: { scope: :alert_id }

  scope :unread, -> { where(read_at: nil) }
  scope :unsent, -> { where(sent_at: nil) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :not_snoozed, -> { where("snoozed_until IS NULL OR snoozed_until <= ?", Date.current) }

  def read?
    read_at.present?
  end

  def sent?
    sent_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  def mark_as_sent!
    update!(sent_at: Time.current) unless sent?
  end
end
