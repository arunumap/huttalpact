class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :admin_session
  attribute :organization

  delegate :user, to: :session, allow_nil: true
  delegate :admin_user, to: :admin_session, allow_nil: true
end
