class AddBroadcastStartedAtToStreamSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :stream_sessions, :broadcast_started_at, :datetime
    add_index :stream_sessions, :broadcast_started_at
  end
end
