# frozen_string_literal: true

module Admin
  module StoreBans
    class RevokeService
      Result = Data.define(:store_ban, :revoked)

      def initialize(store_ban:, actor:, reason: nil)
        @store_ban = store_ban
        @actor = actor
        @reason = reason
      end

      def call
        return Result.new(store_ban: @store_ban, revoked: false) if @store_ban.revoked?

        @store_ban.update!(
          revoked_at: Time.current,
          revoked_by_user: @actor,
          revocation_reason: @reason
        )

        Result.new(store_ban: @store_ban, revoked: true)
      end
    end
  end
end
