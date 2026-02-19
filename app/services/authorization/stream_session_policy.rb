# frozen_string_literal: true

module Authorization
  class StreamSessionPolicy < ApplicationPolicy
    def publish_token?
      return false unless user.present?

      booth = record.booth

      # 上位（store_admin/system_admin）は、所属 store の booth なら publisher token を許可（cast兼務）
      if user.at_least?(:store_admin)
        return true if user.system_admin?
        return user.admin_of_store?(booth.store_id)
      end

      # cast の基本条件
      return false unless BoothPolicy.new(user, booth).cast_operate?

      # フェーズ1: 担当cast（primary）が設定されている場合は、その1人だけ許可
      primary_cast_user_id = booth.primary_cast_user_id
      if primary_cast_user_id.present?
        return primary_cast_user_id == user.id
      end

      # 担当未設定の暫定措置：
      booth.cast_users.exists?(id: user.id) ||
        record.started_by_cast_user_id == user.id
    end

    def view_token?
      return false unless user.present?

      # viewer: customer または admin（store_admin/system_admin）
      allowed =
        user.customer? ||
        BoothPolicy.new(user, record.booth).admin_operate?

      return false unless allowed

      # BAN は customer のみ対象（StoreBanCheckerの仕様に合わせる）
      checker = StoreBanChecker.new(store: record.store, user: user)
      !checker.banned?
    end
  end
end
