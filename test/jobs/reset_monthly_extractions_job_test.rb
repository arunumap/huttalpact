require "test_helper"

class ResetMonthlyExtractionsJobTest < ActiveJob::TestCase
  test "resets extraction counts for organizations whose billing period has rolled over" do
    org = organizations(:one)
    org.update!(ai_extractions_count: 5, ai_extractions_reset_at: 2.months.ago)

    ResetMonthlyExtractionsJob.perform_now

    assert_equal 0, org.reload.ai_extractions_count
    assert_in_delta Time.current, org.ai_extractions_reset_at, 2.seconds
  end

  test "does not reset organizations still within their billing period" do
    org = organizations(:one)
    org.update!(ai_extractions_count: 3, ai_extractions_reset_at: Time.current)

    ResetMonthlyExtractionsJob.perform_now

    assert_equal 3, org.reload.ai_extractions_count
  end

  test "does not affect organizations with zero count" do
    org = organizations(:one)
    org.update!(ai_extractions_count: 0)

    ResetMonthlyExtractionsJob.perform_now
    assert_equal 0, org.reload.ai_extractions_count
  end
end
