# frozen_string_literal: true

module Admin
  module CommentReports
    class RejectService
      class StoreMismatchError < StandardError; end

      def initialize(comment:, current_store:)
        @comment = comment
        @current_store = current_store
      end

      def call
        validate!

        CommentReport
          .where(comment_id: @comment.id, store_id: @current_store.id, status: :pending)
          .update_all(status: CommentReport.statuses.fetch(:rejected), updated_at: Time.current)
      end

      private

      def validate!
        return if @comment.stream_session.store_id == @current_store.id

        raise StoreMismatchError
      end
    end
  end
end
