class RetryPendingPublisherDisconnectsJob < ApplicationJob
  queue_as :default

  def perform
    StreamPublisherConnection.disconnect_retryable
      .where("disconnect_attempts >= ? OR next_disconnect_retry_at IS NULL OR next_disconnect_retry_at <= ?",
        StreamPublisherConnection::MAX_DISCONNECT_ATTEMPTS, Time.current).find_each do |connection|
        Ivs::DisconnectPublisherConnectionService.enqueue(connection.id)
      end
  end
end
