module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end

  def sign_in_as_admin(admin_user)
    Current.admin_session = admin_user.admin_sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:admin_session_id] = Current.admin_session.id
      cookies["admin_session_id"] = cookie_jar[:admin_session_id]
    end
  end

  def sign_out_admin
    Current.admin_session&.destroy!
    cookies.delete("admin_session_id")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
