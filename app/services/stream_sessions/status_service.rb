# frozen_string_literal: true

module StreamSessions
  class StatusService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class NoCurrentSession < Error; end
    class InvalidTransition < Error; end
    class AnotherBoothAlreadyLive < Error; end

    def initialize(booth:, actor:, to_status:, attempt_id: nil)
      @booth, @actor, @to_status, @attempt_id = booth, actor, to_status.to_s, attempt_id
    end

    def call
      PublisherControl.with_user_lock(@actor) do
        booth = Booth.lock.find(@booth.id)
        session = booth.current_stream_session
        raise NoCurrentSession unless session

        PublisherControl.validate!(session, booth, @actor)
        attempt = session.stream_publish_attempts.open.find_by(request_id: @attempt_id, user: @actor)
        raise NotAuthorized, "現在の配信接続から操作してください" unless session.broadcaster?(@actor) && attempt&.usable? && attempt.confirmed_at
        unless %w[live away].include?(booth.status) && %w[live away].include?(@to_status)
          raise InvalidTransition, "配信開始はIVS確認後に確定します"
        end

        booth.update!(status: @to_status, last_online_at: Time.current)
        booth
      end
    end
  end
end
