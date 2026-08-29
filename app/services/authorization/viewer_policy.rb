# frozen_string_literal: true

module Authorization
  class ViewerPolicy < ApplicationPolicy
    def viewer?
      true
    end

    def view_token?
      # BAN は customer のみ対象（現行仕様維持）
      checker = StoreBanChecker.new(store: record.store, user: user)
      !checker.banned?
    end

    def ping_presence?
      interactive_viewer?
    end

    def create_comment?
      interactive_viewer?
    end

    def create_drink_order?
      interactive_viewer?
    end

    private

    def interactive_viewer?
      user.present? && view_token?
    end
  end
end
