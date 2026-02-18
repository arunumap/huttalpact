class MemberRemovalService
  Result = Struct.new(:success?, :error, keyword_init: true)

  def self.call(membership:, performed_by:)
    new(membership:, performed_by:).call
  end

  def initialize(membership:, performed_by:)
    @membership = membership
    @performed_by = performed_by
    @organization = membership.organization
    @user = membership.user
  end

  def call
    return Result.new(success?: false, error: "Cannot remove the organization owner") if @membership.owner?

    ActiveRecord::Base.transaction do
      reassign_contracts!
      @membership.destroy!
    end

    log_removal

    Result.new(success?: true, error: nil)
  rescue => e
    Rails.logger.error("MemberRemovalService error: #{e.message}")
    Result.new(success?: false, error: e.message)
  end

  private

  def reassign_contracts!
    owner = @organization.owner
    return unless owner

    @organization.contracts.where(uploaded_by: @user).update_all(uploaded_by_id: owner.id)
  end

  def log_removal
    return unless Current.user && Current.organization

    AuditLog.create(
      organization: Current.organization,
      user: Current.user,
      action: "member_removed",
      details: "Removed #{@user.full_name} (#{@user.email_address}) from the organization"
    )
  end
end
