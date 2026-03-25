# frozen_string_literal: true

module StreamSessions
  module Comments
    class CreateService
      class RateLimitedError < StandardError; end
      class BoothNotLiveError < StandardError; end

      def initialize(stream_session:, user:, body: nil, kind: Comment::KIND_CHAT, metadata: {}, notify: true)
        @stream_session = stream_session
        @user = user
        @body = body
        @kind = kind.to_s.strip.presence || Comment::KIND_CHAT
        @metadata = normalize_metadata(metadata)
        @notify = notify
      end

      def call
        raise BoothNotLiveError unless booth_allows_comments?
        raise RateLimitedError if chat? && rate_limited?

        comment = Comment.create!(
          stream_session: @stream_session,
          booth_id: @stream_session.booth_id,
          user: @user,
          body: @body,
          kind: @kind,
          metadata: @metadata
        )

        CommentNotifier.append(comment) if @notify
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

      def chat?
        @kind == Comment::KIND_CHAT
      end

      def normalize_metadata(metadata)
        case metadata
        when ActionController::Parameters
          metadata.to_unsafe_h
        when Hash
          metadata
        when nil
          {}
        else
          metadata.respond_to?(:to_h) ? metadata.to_h : {}
        end
      rescue TypeError, NoMethodError
        {}
      end
    end
  end
end
