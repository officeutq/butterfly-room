# frozen_string_literal: true

module StreamSessions
  module Comments
    class CreateService
      class RateLimitedError < StandardError; end
      class BoothNotLiveError < StandardError; end

      def initialize(stream_session:, user:, body:)
        @stream_session = stream_session
        @user = user
        @body = body.to_s.strip
      end

      def call
        raise ActiveRecord::RecordInvalid.new(Comment.new) if @body.blank?
        raise BoothNotLiveError unless booth_allows_comments?
        raise RateLimitedError if rate_limited?

        comment = Comment.create!(
          stream_session: @stream_session,
          booth_id: @stream_session.booth_id,
          user: @user,
          body: @body
        )

        CommentNotifier.append(comment)
        comment
      end

      private

      def booth_allows_comments?
        booth = @stream_session.booth
        booth.live? || booth.away?
      end

      def rate_limited?
        Comment.where(user_id: @user.id, stream_session_id: @stream_session.id)
               .where("created_at >= ?", 1.second.ago)
               .exists?
      end
    end
  end
end
