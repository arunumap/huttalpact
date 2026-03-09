class ContractDraftCreatorService
  def initialize(user:, organization:, files:, contract_type:)
    @user = user
    @organization = organization
    @files = Array(files).compact_blank
    @contract_type = contract_type.presence
  end

  def call
    raise ArgumentError, "No files provided" if @files.empty?
    if @contract_type.present? && !Contract::CONTRACT_TYPES.include?(@contract_type)
      raise ArgumentError, "Invalid contract type"
    end

    Contract.transaction do
      contract = Contract.new(
        organization: @organization,
        status: "draft",
        title: "Untitled Draft",
        uploaded_by: @user,
        contract_type: @contract_type
      )
      contract.save!

      @files.each do |file|
        contract.contract_documents.create!(file: file)
      end

      contract
    end
  end
end
