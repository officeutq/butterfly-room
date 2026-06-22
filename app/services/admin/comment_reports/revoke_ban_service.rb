# frozen_string_literal: true

module Admin
  module CommentReports
    class RevokeBanService
      REVOCATION_REASON = "comment_report_revoke"

      class StoreMismatchError < StandardError; end
      class UnsupportedReportedUserError < StandardError; end
      class RevokeTargetNotFoundError < StandardError; end

      def initialize(comment:, actor:, current_store:)
        @comment = comment
        @actor = actor
        @current_store = current_store
      end

      def call
        validate!

        store_ban = revoke_target
        raise RevokeTargetNotFoundError if store_ban.blank?

        Admin::StoreBans::RevokeService.new(
          store_ban: store_ban,
          actor: @actor,
          reason: REVOCATION_REASON
        ).call
      end

      private

      def validate!
        raise StoreMismatchError unless @comment.stream_session.store_id == @current_store.id
        raise UnsupportedReportedUserError unless reported_user.customer?
      end

      def reported_user
        @comment.user
      end

      def revoke_target
        @current_store
          .store_bans
          .active
          .includes(:customer_user, source_comment: :stream_session)
          .where(customer_user: reported_user)
          .find { |store_ban| revokable_store_ban?(store_ban) }
      end

      def revokable_store_ban?(store_ban)
        return false unless store_ban.store_id == @current_store.id
        return false unless store_ban.customer_user_id == reported_user.id
        return false unless store_ban.customer_user&.customer?
        return false if store_ban.source_comment_id.blank?

        source_comment = store_ban.source_comment
        return false if source_comment.blank?
        return false unless source_comment.user_id == store_ban.customer_user_id

        source_comment.stream_session&.store_id == @current_store.id
      end
    end
  end
end
