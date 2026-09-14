module Ivs
  class DisconnectPublisherConnectionService
    RETRY_DELAYS = [ 5.seconds, 30.seconds, 2.minutes, 10.minutes, 30.minutes ].freeze

    def initialize(connection_id:)
      @connection_id = connection_id
    end

    def call
      connection = StreamPublisherConnection.find(@connection_id)
      connection.with_lock do
        return connection if connection.disconnect_requested_at.nil? || connection.released_at.present?

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
          connection.next_disconnect_retry_at = RETRY_DELAYS.fetch([ connection.disconnect_attempts - 1, RETRY_DELAYS.size - 1 ].min).from_now
        end
        connection.save!
      end
      connection
    end
  end
end
