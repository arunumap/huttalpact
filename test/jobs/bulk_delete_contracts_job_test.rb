require "test_helper"

class BulkDeleteContractsJobTest < ActiveJob::TestCase
  test "deletes selected contracts, tracks progress, and cleans Active Storage attachments" do
    organization = organizations(:one)
    user = users(:one)
    contract = contracts(:hvac_maintenance)
    document = contract_documents(:completed_doc)
    document.file.attach(io: StringIO.new("bulk delete cleanup"), filename: "cleanup.txt", content_type: "text/plain")
    assert document.file.attached?

    operation = BulkDeleteOperation.create!(
      organization: organization,
      user: user,
      requested_count: 1
    )

    assert_difference "Contract.count", -1 do
      assert_difference "AuditLog.count", 1 do
        assert_difference "ActiveStorage::Attachment.count", -1 do
          BulkDeleteContractsJob.perform_now(operation.id, [ contract.id ])
        end
      end
    end

    operation.reload
    assert_equal BulkDeleteOperation::STATUS_COMPLETED, operation.status
    assert_equal 1, operation.requested_count
    assert_equal 1, operation.processed_count
    assert_equal 1, operation.deleted_count
    assert_equal 0, operation.failed_count
    assert_not_nil operation.completed_at

    log = AuditLog.order(created_at: :desc).first
    assert_equal "deleted", log.action
    assert_match "Deleted contract via bulk action", log.details
  end

  test "marks failures when selected contract is outside operation organization" do
    organization = organizations(:one)
    user = users(:one)
    contract = contracts(:hvac_maintenance)
    other_org_contract = contracts(:other_org_contract)

    operation = BulkDeleteOperation.create!(
      organization: organization,
      user: user,
      requested_count: 2
    )

    BulkDeleteContractsJob.perform_now(operation.id, [ contract.id, other_org_contract.id ])

    assert_not Contract.exists?(contract.id)
    assert Contract.exists?(other_org_contract.id)

    operation.reload
    assert_equal BulkDeleteOperation::STATUS_COMPLETED_WITH_ERRORS, operation.status
    assert_equal 2, operation.processed_count
    assert_equal 1, operation.deleted_count
    assert_equal 1, operation.failed_count
  end
end
