# frozen_string_literal: true

module Authorization
  class ViewerPolicy < ApplicationPolicy
    def viewer?
      user.present?
    end

    def view_token?
      return false unless viewer?

      # BAN は customer のみ対象（現行仕様維持）
      checker = StoreBanChecker.new(store: record.store, user: user)
      !checker.banned?
    end

    def ping_presence?
      viewer?
    end

    def create_comment?
      viewer?
    end

    def create_drink_order?
      viewer?
    end
  end
end
