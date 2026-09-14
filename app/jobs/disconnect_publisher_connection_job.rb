class DisconnectPublisherConnectionJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    Ivs::DisconnectPublisherConnectionService.new(connection_id: connection_id, respect_retry_at: true).call
  end
end
