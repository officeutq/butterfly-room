# frozen_string_literal: true

module Authorization
  class StreamSessionPolicy < ApplicationPolicy
    def publish_token?
      return false unless user.present?

      # cast/system_admin の基本条件
      return false unless BoothPolicy.new(user, record.booth).cast_operate?

      # 「その booth の cast」であること
      # ただし、cast所属（booth.cast_users）が未整備でも、
      # セッション開始者本人は publisher token を取得できるようにする
      # TODO: booth.cast_users の整備
      record.booth.cast_users.exists?(id: user.id) ||
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
