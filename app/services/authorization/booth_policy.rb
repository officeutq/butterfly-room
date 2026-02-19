module Authorization
  class BoothPolicy < ApplicationPolicy
    def show?
      true
    end

    def cast_operate?
      return false if user.blank?
      user.at_least?(:cast)
    end

    def admin_operate?
      return false if user.blank?
      user.at_least?(:store_admin)
    end

    def edit?
      update?
    end

    def create?
      return false if user.blank?
      return true if user.system_admin?
      return false unless user.store_admin?

      # store_admin：自分の store の booth のみ作成可
      user.store_memberships.admin_only.exists?(store_id: record.store_id)
    end

    def update?
      return false if user.blank?
      return true if user.system_admin?
      return false if user.customer?

      if user.store_admin?
        # store_admin：自分の store の booth のみ編集可
        return user.store_memberships.admin_only.exists?(store_id: record.store_id)
      end

      if user.cast?
        # cast：所属する booth のみ編集可
        return record.booth_casts.exists?(cast_user_id: user.id)
      end

      false
    end
  end
end
