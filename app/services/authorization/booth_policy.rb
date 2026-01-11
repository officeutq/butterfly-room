module Authorization
  class BoothPolicy < ApplicationPolicy
    def show?
      true
    end

    def cast_operate?
      user.cast? || user.system_admin?
    end

    def admin_operate?
      user.store_admin? || user.system_admin?
    end
  end
end
