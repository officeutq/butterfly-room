module StreamSessions
  class ReportPublisherConfirmationFailureService
    class RetryExhausted < StandardError; end

    def initialize(stream_session:, actor:, request_id:, generation:)
      @stream_session, @actor, @request_id = stream_session, actor, request_id
      @generation = PublisherControl.generation(generation)
    end

    def call
      booth = @stream_session.booth
      booth.with_lock do
        @stream_session.lock!
        unless PublisherControl.active_actor?(@actor) && Authorization::StreamSessionPolicy.new(@actor, @stream_session).publish_token?
          raise PublisherControl::Error.new(code: "forbidden", message: "配信を操作する権限がありません", booth: booth, status: :forbidden)
        end
        connection = @stream_session.stream_publisher_connections.lock.find_by(request_id: @request_id) if PublisherControl.valid_request_id?(@request_id)
        unless connection && connection.user_id == @actor.id && connection.generation == @generation &&
            @stream_session.publisher_generation == @generation && @stream_session.current_publisher_connection_id == connection.id &&
            !@stream_session.ended? && connection.confirmed_at.nil? && connection.disconnect_requested_at.nil?
          raise PublisherControl::Error.new(code: "stale_publisher_request", message: "配信の状態が更新されています。画面を読み込み直してください", booth: booth)
        end
        return if connection.confirmation_failure_reported_at

        connection.update!(confirmation_failure_reported_at: Time.current)
        ActiveRecord.after_all_transactions_commit do
          Rails.error.report(RetryExhausted.new("Publisher confirmation retries exhausted"), handled: true,
            severity: :error, source: "application", context: {
              log_source: "application", request_id: connection.request_id, actor_user_id: connection.user_id,
              store_id: @stream_session.store_id, stream_session_id: @stream_session.id
            })
        end
      end
    end
  end
end
