module Ivs
  class DisconnectPublisherConnectionService
    RETRY_DELAYS = [ 0.5.seconds, 1.second, 2.seconds ].freeze
    class RetryExhausted < StandardError; end

    # 旧ジョブの引数を受けても、全入口で待機予定・上限を守る。
    def initialize(connection_id:, respect_retry_at: true)
      @connection_id = connection_id
    end

    def call
      connection = StreamPublisherConnection.find(@connection_id)
      # 終了・取消・退会等の外側処理が戻ったとき、AWSだけ切断された状態を作らない。
      # 回数も外側のrollbackに巻き込まれないよう、意図の確定後に試行する。
      ActiveRecord.after_all_transactions_commit { attempt }
      connection.reload
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
      connection.with_lock do
        return if connection.disconnect_requested_at.nil? || connection.released_at || connection.disconnect_failed_at
        # 導入前に4回以上試行された行も、5回目を実行せず終端へ移す。
        return exhaust!(connection) if connection.disconnect_attempts >= StreamPublisherConnection::MAX_DISCONNECT_ATTEMPTS
        return if connection.next_disconnect_retry_at&.future?

        wait_until = ReserveDisconnectSlotService.call(stage_arn: connection.ivs_stage_arn)
        if wait_until
          connection.update!(next_disconnect_retry_at: wait_until)
          schedule(connection)
          return
        end

        connection.disconnect_attempts += 1
        begin
          if connection.ivs_participant_id.blank?
            connection.last_disconnect_error = "participant_id_missing"
          else
            # SDK内で追加の再試行を行わず、保存済み回数だけで管理する。
            Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1"),
              retry_limit: 0, max_attempts: 1).disconnect_participant(
                stage_arn: connection.ivs_stage_arn, participant_id: connection.ivs_participant_id
              )
            connection.disconnected_at = Time.current
            connection.released_at = connection.disconnected_at
            connection.last_disconnect_error = nil
            connection.next_disconnect_retry_at = nil
          end
        rescue Aws::IVSRealTime::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError => error
          connection.last_disconnect_error = error.class.name
        end

        if connection.released_at
          connection.save!
        elsif connection.disconnect_attempts >= StreamPublisherConnection::MAX_DISCONNECT_ATTEMPTS
          exhaust!(connection)
        else
          connection.next_disconnect_retry_at = RETRY_DELAYS.fetch(connection.disconnect_attempts - 1).from_now
          connection.save!
          schedule(connection)
        end
      end
    end

    def schedule(connection)
      time = connection.next_disconnect_retry_at
      ActiveRecord.after_all_transactions_commit { self.class.enqueue(connection.id, wait_until: time) }
    end

    def exhaust!(connection)
      connection.disconnect_failed_at = Time.current
      connection.next_disconnect_retry_at = nil
      connection.save!
      ActiveRecord.after_all_transactions_commit do
        # 任意のAWS応答本文を例外メッセージ・エラーログへ渡さない。
        Rails.logger.error("publisher_disconnect_exhausted connection_id=#{connection.id} reason=#{connection.disconnect_reason} " \
          "error=#{connection.last_disconnect_error}")
        Rails.error.report(RetryExhausted.new("Publisher disconnect retries exhausted"), handled: true,
          severity: :error, source: "application", context: {
            log_source: "application", actor_user_id: connection.user_id, store_id: connection.stream_session.store_id,
            stream_session_id: connection.stream_session_id, request_id: connection.request_id
          })
      end
    end
  end
end
