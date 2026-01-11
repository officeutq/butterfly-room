class AddCurrentStreamSessionIdFkToBooths < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :booths, :stream_sessions, column: :current_stream_session_id
  end
end
