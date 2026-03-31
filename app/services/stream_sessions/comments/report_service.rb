# frozen_string_literal: true

module StreamSessions
  module Comments
    class ReportService
      class NotAllowedError < StandardError; end
      class AlreadyReportedError < StandardError; end

      def initialize(comment:, reporter_user:)
        @comment = comment
        @reporter_user = reporter_user
      end

      def call
        validate!

        CommentReport.create!(
          comment: @comment,
          reporter_user: @reporter_user,
          reported_user: @comment.user,
          store: @comment.stream_session.store,
          booth: @comment.booth,
          stream_session: @comment.stream_session,
          status: :pending
        )
      end

      private

      def validate!
        raise NotAllowedError unless @comment.chat?
        raise NotAllowedError if @comment.user_id == @reporter_user.id

        if CommentReport.exists?(comment_id: @comment.id, reporter_user_id: @reporter_user.id)
          raise AlreadyReportedError
        end
      end
    end
  end
end
