class RemoveDescriptionFromStreamSessions < ActiveRecord::Migration[8.1]
  def up
    remove_column :stream_sessions, :description, :text
  end

  def down
    add_column :stream_sessions, :description, :text
  end
end
