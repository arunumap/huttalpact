require "test_helper"

class Admin::JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    sign_in_as_admin(@admin_user)
  end

  # ── Index (Solid Queue unavailable) ──

  test "index renders when solid queue is unavailable" do
    get admin_jobs_path
    assert_response :success
    assert_select "p", text: /Solid Queue is not available/
  end

  # ── Failed (Solid Queue unavailable) ──

  test "failed redirects when solid queue unavailable" do
    get failed_admin_jobs_path
    assert_redirected_to admin_jobs_path
  end

  # ── Recurring (Solid Queue unavailable) ──

  test "recurring redirects when solid queue unavailable" do
    get recurring_admin_jobs_path
    assert_redirected_to admin_jobs_path
  end

  # ── Show (Solid Queue unavailable) ──

  test "show redirects when solid queue unavailable" do
    get admin_job_path(id: 1)
    assert_redirected_to admin_jobs_path
  end

  # ── Requires Auth ──

  test "requires admin authentication" do
    sign_out_admin
    get admin_jobs_path
    assert_redirected_to new_admin_session_path
  end
end
