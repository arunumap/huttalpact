class ContractDraftCreatorService
  def initialize(user:, organization:, files:)
    @user = user
    @organization = organization
    @files = Array(files).compact_blank
  end

  def call
    raise ArgumentError, "No files provided" if @files.empty?

    Contract.transaction do
      contract = Contract.new(
        organization: @organization,
        status: "draft",
        title: "Untitled Draft",
        uploaded_by: @user
      )
      contract.save!

      @files.each do |file|
        contract.contract_documents.create!(file: file)
      end

      contract
    end
  end
end
