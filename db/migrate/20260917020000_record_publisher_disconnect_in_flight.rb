class RecordPublisherDisconnectInFlight < ActiveRecord::Migration[8.1]
  def change
    add_column :stream_publisher_connections, :disconnect_in_flight_at, :datetime
  end
end
