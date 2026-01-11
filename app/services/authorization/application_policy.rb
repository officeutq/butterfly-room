module Authorization
  class ApplicationPolicy
    def initialize(user, record)
      @user = user
      @record = record
    end

    private

    attr_reader :user, :record
  end
end
