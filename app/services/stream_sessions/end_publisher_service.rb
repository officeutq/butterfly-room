module StreamSessions
  class EndPublisherService
    def initialize(stream_session:, actor:, request_id:, generation:, mode: :normal)
      @stream_session = stream_session
      @actor = actor
      @request_id = request_id.presence
      @generation = PublisherControl.generation(generation)
      @mode = mode
    end

    def call
      @booth = @stream_session.booth
      @booth.with_lock do
        @stream_session.lock!
        authorize!
        validate_request!
        return @stream_session if @stream_session.ended?

        unless !@booth.archived? && @booth.current_stream_session_id == @stream_session.id &&
            @stream_session.live? && @stream_session.ended_at.nil? && %w[standby live away].include?(@booth.status)
          reject!("not_joinable", "配信の状態が更新されています。画面を読み込み直してください")
        end
        unless %i[not_started recorded].include?(@stream_session.publisher_recording_state)
          reject!("publisher_state_unavailable", "配信者の記録を確認できません。状態を確認してください", status: :service_unavailable)
        end

        @stream_session.update!(publisher_generation: @generation + 1)
        @stream_session.stream_publisher_connections.unreleased.order(:id).lock.each do |connection|
          connection.update!(disconnect_requested_at: Time.current, disconnect_reason: "end")
          Ivs::DisconnectPublisherConnectionService.new(connection_id: connection.id).call
        end
        refund = DrinkOrders::RefundService.new(stream_session: @stream_session).call!
        @stream_session.update!(status: :ended, ended_at: Time.current)
        @booth.update!(status: :offline, current_stream_session_id: nil)
        notify_after_commit(refund.wallet_ids)
        @stream_session
      end
    end

    private

    def authorize!
      allowed = PublisherControl.active_actor?(@actor) && Authorization::BoothPolicy.new(@actor, @booth).update?
      allowed &&= @actor.at_least?(:store_admin) if @mode == :force
      allowed &&= %i[normal force cleanup].include?(@mode)
      if @mode == :normal && @stream_session.broadcast_started_at.present?
        allowed &&= @stream_session.actual_publisher?(@actor) &&
          Authorization::StreamSessionPolicy.new(@actor, @stream_session).publish_token?
      end
      reject!("forbidden", "この配信を終了する権限がありません", status: :forbidden) unless allowed
    end

    def validate_request!
      expected = @stream_session.publisher_generation - (@stream_session.ended? ? 1 : 0)
      stale! unless @generation && @generation == expected
      return unless @mode == :normal
      return if @stream_session.broadcast_started_at.nil?

      connection = @stream_session.stream_publisher_connections.lock.find_by(id: @stream_session.current_publisher_connection_id)
      # 再試行ジョブは接続行だけを更新するため、取消済みの参照が残る場合がある。
      if connection&.disconnect_reason == "cancel" && connection.released_at && connection.generation + 1 == expected
        connection = nil
      end
      if connection
        stale! unless PublisherControl.valid_request_id?(@request_id) && connection.request_id == @request_id.downcase &&
          connection.generation == @generation
      else
        # 未発行の準備、または本人の未確定な復帰取消後には現在の接続がない。
        stale! if @request_id
      end
    end

    def notify_after_commit(wallet_ids)
      ActiveRecord.after_all_transactions_commit do
        [ -> { StreamSessionNotifier.broadcast_ended(@stream_session, forced: @mode != :normal) },
          -> { StreamSessionNotifier.broadcast_stream_state(booth: @booth) },
          -> { WalletNotifier.broadcast_balance_for_wallet_ids(wallet_ids) } ].each do |notification|
          begin
            notification.call
          rescue StandardError => error
            Rails.logger.error("publisher_end_notification_failed stream_session_id=#{@stream_session.id} error=#{error.class.name}")
          end
        end
      end
    end

    def stale!
      reject!("stale_publisher_request", "配信の状態が更新されています。画面を読み込み直してください")
    end

    def reject!(code, message, status: :conflict)
      raise PublisherControl::Error.new(code: code, message: message, booth: @booth, status: status)
    end
  end
end
