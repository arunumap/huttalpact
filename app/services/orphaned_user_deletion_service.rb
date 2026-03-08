class OrphanedUserDeletionService
  def initialize(user)
    @user = user
  end

  def delete!
    raise ArgumentError, "User is still associated with an organization." unless @user.without_organizations?

    @user.destroy!
  end
end
