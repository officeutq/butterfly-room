class RetryPendingPublisherDisconnectsJob < ApplicationJob
  queue_as :default

  def perform
    StreamPublisherConnection.disconnect_pending.unreleased
      .where("next_disconnect_retry_at IS NULL OR next_disconnect_retry_at <= ?", Time.current).find_each do |connection|
        Ivs::DisconnectPublisherConnectionService.enqueue(connection.id)
      end
  end
end
