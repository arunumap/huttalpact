require "test_helper"

class ResetMonthlyExtractionsJobTest < ActiveJob::TestCase
  test "resets extraction counts for organizations with usage" do
    org = organizations(:one)
    org.update!(ai_extractions_count: 5, ai_extractions_reset_at: 1.month.ago)

    org2 = organizations(:two)
    org2.update!(ai_extractions_count: 0)

    ResetMonthlyExtractionsJob.perform_now

    assert_equal 0, org.reload.ai_extractions_count
    assert_in_delta Time.current, org.ai_extractions_reset_at, 2.seconds
    # Org two had 0 count, should not be touched (query filters count > 0)
  end

  test "does not affect organizations with zero count" do
    org = organizations(:one)
    org.update!(ai_extractions_count: 0)

    ResetMonthlyExtractionsJob.perform_now
    assert_equal 0, org.reload.ai_extractions_count
  end
end
