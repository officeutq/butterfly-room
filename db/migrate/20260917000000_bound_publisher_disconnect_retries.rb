class BoundPublisherDisconnectRetries < ActiveRecord::Migration[8.1]
  def change
    add_column :stream_publisher_connections, :disconnect_failed_at, :datetime

    create_table :ivs_disconnect_limits, id: :string do |t|
      t.datetime :next_available_at, null: false
    end
  end
end
