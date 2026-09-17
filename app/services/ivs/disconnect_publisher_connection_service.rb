module Ivs
  class DisconnectPublisherConnectionService
    RETRY_DELAYS = [ 0.5.seconds, 1.second, 2.seconds ].freeze
    RESPONSE_DEADLINE = 30.seconds
    class RetryExhausted < StandardError; end
    class PersistenceFailed < StandardError; end
    class RecoveryFailed < StandardError; end

    # 旧ジョブの引数を受けても、全入口で待機予定・上限を守る。
    def initialize(connection_id:, respect_retry_at: true)
      @connection_id = connection_id
    end

    def call
      connection = StreamPublisherConnection.find(@connection_id)
      # 外側の終了・取消・退会等がrollbackされたらAWSへ送らない。
      ActiveRecord.after_all_transactions_commit { attempt }
      connection.reload
    end

    # Webや通常ジョブへ公開しない、保存済み対象に限定した運用の1回だけの再実行。
    # 回数・最終失敗日時をリセットしない。新しい自動再試行サイクルも開始しない。
    def recover_once(request_id:, participant_id:)
      @recovery_identity = [ request_id, participant_id ]
      call
    end

    def self.enqueue(connection_id, wait_until: nil)
      job = DisconnectPublisherConnectionJob
      job = job.set(wait_until: wait_until) if wait_until
      job.perform_later(connection_id)
    rescue StandardError => error
      Rails.logger.error("publisher_disconnect_enqueue_failed connection_id=#{connection_id} error=#{error.class.name}")
    end

    private

    def attempt
      connection = StreamPublisherConnection.find(@connection_id)
      number = reserve_attempt(connection)
      return unless number

      failure = disconnect(connection)
      connection.with_lock do
        # 遅い応答で、後続試行の結果を上書きしない。
        return if connection.released_at || connection.disconnect_attempts != number || connection.disconnect_in_flight_at.nil?

        connection.disconnect_in_flight_at = nil
        if failure.nil?
          connection.update!(disconnected_at: Time.current, released_at: Time.current,
            last_disconnect_error: nil, next_disconnect_retry_at: nil)
          notify_after_commit(connection)
        else
          fail_attempt(connection, failure)
        end
      end
    rescue ActiveRecord::ActiveRecordError => error
      # 試行予約は既に確定済み。保存失敗で回数を戻したり、終了通知を止めたりしない。
      report(connection, PersistenceFailed, error.class.name) if connection
      self.class.enqueue(@connection_id, wait_until: RESPONSE_DEADLINE.from_now)
    end

    def reserve_attempt(connection)
      number = nil
      connection.with_lock do
        return if connection.disconnect_requested_at.nil? || connection.released_at
        if @recovery_identity
          unless [ connection.request_id, connection.ivs_participant_id ] == @recovery_identity && connection.disconnect_state == "failed"
            raise ArgumentError, "指定した未解決接続と一致しません"
          end
        else
          return if connection.disconnect_failed_at
        end
        if connection.disconnect_in_flight_at
          return if connection.next_disconnect_retry_at&.future?

          # プロセス停止やDB保存失敗で応答を保存できなかった回も消費済みにする。
          connection.disconnect_in_flight_at = nil
          fail_attempt(connection, "response_unconfirmed")
          return
        end
        unless @recovery_identity
          if connection.disconnect_attempts >= StreamPublisherConnection::MAX_DISCONNECT_ATTEMPTS
            exhaust!(connection)
            return
          end
          return if connection.next_disconnect_retry_at&.future?
        end

        wait_until = ReserveDisconnectSlotService.call(stage_arn: connection.ivs_stage_arn)
        if wait_until
          raise ArgumentError, "呼出間隔の制限中です。少し待って同じ指定で実行してください" if @recovery_identity

          connection.update!(next_disconnect_retry_at: wait_until)
          schedule(connection)
          return
        end
        # API通信より先に回数をcommitする。送信前にプロセスが落ちても安全側に1回消費する。
        number = connection.disconnect_attempts + 1
        connection.update!(disconnect_attempts: number, disconnect_in_flight_at: Time.current,
          next_disconnect_retry_at: RESPONSE_DEADLINE.from_now)
        schedule(connection)
      end
      number
    end

    def disconnect(connection)
      return "participant_id_missing" if connection.ivs_participant_id.blank?

      Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1"), retry_limit: 0, max_attempts: 1,
        http_open_timeout: 5, http_read_timeout: 5).disconnect_participant(
          stage_arn: connection.ivs_stage_arn, participant_id: connection.ivs_participant_id
        )
      nil
    rescue Aws::IVSRealTime::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError => error
      error.class.name
    end

    def fail_attempt(connection, failure)
      connection.last_disconnect_error = failure
      if @recovery_identity
        connection.update!(next_disconnect_retry_at: nil)
        notify_after_commit(connection)
        ActiveRecord.after_all_transactions_commit { report(connection, RecoveryFailed, failure) }
      elsif connection.disconnect_attempts >= StreamPublisherConnection::MAX_DISCONNECT_ATTEMPTS
        exhaust!(connection)
      else
        connection.update!(next_disconnect_retry_at: RETRY_DELAYS.fetch(connection.disconnect_attempts - 1).from_now)
        schedule(connection)
      end
    end

    def schedule(connection)
      time = connection.next_disconnect_retry_at
      ActiveRecord.after_all_transactions_commit { self.class.enqueue(connection.id, wait_until: time) }
    end

    def notify_after_commit(connection)
      ActiveRecord.after_all_transactions_commit { StreamSessionNotifier.broadcast_publisher_disconnect(connection) }
    end

    def exhaust!(connection)
      connection.update!(disconnect_failed_at: Time.current, next_disconnect_retry_at: nil)
      notify_after_commit(connection)
      ActiveRecord.after_all_transactions_commit { report(connection, RetryExhausted, connection.last_disconnect_error) }
    end

    def report(connection, error_class, cause)
      Rails.logger.error("publisher_disconnect_error connection_id=#{connection.id} reason=#{connection.disconnect_reason} error=#{cause}")
      Rails.error.report(error_class.new("Publisher disconnect failed"), handled: true, severity: :error, source: "application",
        context: { log_source: "application", request_id: connection.request_id, actor_user_id: connection.user_id,
          store_id: connection.stream_session.store_id, stream_session_id: connection.stream_session_id })
    end
  end
end
