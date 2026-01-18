# frozen_string_literal: true

module StreamSessions
  module Comments
    class CreateService
      class BannedError < StandardError; end
      class RateLimitedError < StandardError; end

      def initialize(stream_session:, user:, body:)
        @stream_session = stream_session
        @user = user
        @body = body.to_s.strip
      end

      def call
        raise ActiveRecord::RecordInvalid.new(Comment.new) if @body.blank?
        raise BannedError if banned?
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

      def banned?
        return false unless @user.customer?
        StoreBan.exists?(store_id: @stream_session.store_id, customer_user_id: @user.id)
      end

      def rate_limited?
        Comment.where(user_id: @user.id, stream_session_id: @stream_session.id)
               .where("created_at >= ?", 1.second.ago)
               .exists?
      end
    end
  end
end
