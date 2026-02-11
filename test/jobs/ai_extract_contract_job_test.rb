require "test_helper"

class AiExtractContractJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @contract = contracts(:hvac_maintenance)
  end

  test "calls ContractAiExtractorService in full mode" do
    service_called = false
    fake_service = Object.new
    fake_service.define_singleton_method(:call) { service_called = true; { "title" => "Test" } }

    ContractAiExtractorService.stub(:new, ->(*_args, **_kwargs) { fake_service }) do
      AiExtractContractJob.perform_now(@contract.id)
    end

    assert service_called, "Expected ContractAiExtractorService#call to be invoked"
  end

  test "passes incremental mode when new_document_id provided" do
    received_mode = nil
    fake_service = Object.new
    fake_service.define_singleton_method(:call) { { "title" => "Test" } }

    ContractAiExtractorService.stub(:new, ->(_contract, **kwargs) {
      received_mode = kwargs[:mode]
      fake_service
    }) do
      AiExtractContractJob.perform_now(@contract.id, new_document_id: "some-uuid")
    end

    assert_equal :incremental, received_mode
  end

  test "handles missing contract gracefully" do
    assert_nothing_raised do
      AiExtractContractJob.perform_now("nonexistent-uuid")
    end
  end

  test "discards ExtractionError" do
    error_service = Object.new
    error_service.define_singleton_method(:call) do
      raise ContractAiExtractorService::ExtractionError, "Test error"
    end

    ContractAiExtractorService.stub(:new, ->(*_args, **_kwargs) { error_service }) do
      # Should NOT raise — job should discard
      assert_nothing_raised do
        AiExtractContractJob.perform_now(@contract.id)
      end
    end
  end

  test "discards ExtractionLimitReachedError" do
    error_service = Object.new
    error_service.define_singleton_method(:call) do
      raise ContractAiExtractorService::ExtractionLimitReachedError, "Limit reached"
    end

    ContractAiExtractorService.stub(:new, ->(*_args, **_kwargs) { error_service }) do
      # Should NOT raise — job should discard, not retry
      assert_nothing_raised do
        AiExtractContractJob.perform_now(@contract.id)
      end
    end
  end
end
