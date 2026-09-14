module Ivs
  class DisconnectPublisherConnectionService
    RETRY_DELAYS = [ 5.seconds, 30.seconds, 2.minutes, 10.minutes, 30.minutes ].freeze

    def initialize(connection_id:, respect_retry_at: false)
      @connection_id = connection_id
      @respect_retry_at = respect_retry_at
    end

    def call
      connection = StreamPublisherConnection.find(@connection_id)
      connection.with_lock do
        return connection if connection.disconnect_requested_at.nil? || connection.released_at.present?
        return connection if @respect_retry_at && connection.next_disconnect_retry_at&.future?

        connection.disconnect_attempts += 1
        begin
          if connection.ivs_participant_id.blank?
            connection.last_disconnect_error = "participant_id_missing"
          else
            Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1")).disconnect_participant(
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
        if connection.released_at.nil?
          Rails.logger.warn("publisher_disconnect_pending connection_id=#{connection.id} user_id=#{connection.user_id} " \
            "booth_id=#{connection.booth_id} store_id=#{connection.stream_session.store_id} " \
            "stream_session_id=#{connection.stream_session_id} error=#{connection.last_disconnect_error}")
          connection.next_disconnect_retry_at = RETRY_DELAYS.fetch([ connection.disconnect_attempts - 1, RETRY_DELAYS.size - 1 ].min).from_now
        end
        connection.save!
        if connection.released_at.nil?
          ActiveRecord.after_all_transactions_commit do
            self.class.enqueue(connection.id, wait_until: connection.next_disconnect_retry_at)
          end
        end
      end
      connection
    end

    def self.enqueue(connection_id, wait_until: nil)
      job = DisconnectPublisherConnectionJob
      job = job.set(wait_until: wait_until) if wait_until
      job.perform_later(connection_id)
    rescue StandardError => error
      # DBの切断待ちは残るため、毎分の回収処理が再投入できる。
      Rails.logger.error("publisher_disconnect_enqueue_failed connection_id=#{connection_id} error=#{error.class.name}")
    end
  end
end
