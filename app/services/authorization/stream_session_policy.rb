# frozen_string_literal: true

module Authorization
  class StreamSessionPolicy < ApplicationPolicy
    def publish_token?
      return false unless user.present?

      # cast/system_admin の基本条件
      return false unless BoothPolicy.new(user, record.booth).cast_operate?

      booth = record.booth

      # フェーズ1: 担当cast（primary）が設定されている場合は、その1人だけ許可
      primary_cast_user_id = booth.primary_cast_user_id
      if primary_cast_user_id.present?
        return primary_cast_user_id == user.id
      end

      # 担当未設定の暫定措置：
      # booth.cast_users の整備前でも、セッション開始者本人は publisher token を取得できるようにする
      booth.cast_users.exists?(id: user.id) ||
        record.started_by_cast_user_id == user.id
    end

    def view_token?
      return false unless user.present?

      # viewer: customer または admin（store_admin/system_admin）
      allowed =
        user.customer? ||
        BoothPolicy.new(user: user, record: record.booth).admin_operate?

      return false unless allowed

      # BAN は customer のみ対象（StoreBanCheckerの仕様に合わせる）
      checker = StoreBanChecker.new(store: record.store, user: user)
      !checker.banned?
    end
  end
end
