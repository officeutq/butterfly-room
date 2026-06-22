# frozen_string_literal: true

module Admin
  module CommentReports
    class BanService
      BAN_REASON = "コメント通報による対応"

      class StoreMismatchError < StandardError; end
      class UnsupportedReportedUserError < StandardError; end

      def initialize(comment:, actor:, current_store:)
        @comment = comment
        @actor = actor
        @current_store = current_store
      end

      def call
        validate!

        ApplicationRecord.transaction do
          create_store_ban!
          resolve_pending_reports_for_comment!
        end
      end

      private

      def validate!
        raise StoreMismatchError unless @comment.stream_session.store_id == @current_store.id
        raise UnsupportedReportedUserError unless reported_user.customer?
      end

      def reported_user
        @comment.user
      end

      def create_store_ban!
        Admin::StoreBans::CreateService.new(
          store: @current_store,
          customer_user: reported_user,
          actor: @actor,
          reason: BAN_REASON,
          source_comment: @comment
        ).call
      end

      def resolve_pending_reports_for_comment!
        CommentReport
          .where(comment_id: @comment.id, store_id: @current_store.id, status: :pending)
          .update_all(status: CommentReport.statuses.fetch(:resolved), updated_at: Time.current)
      end
    end
  end
end
