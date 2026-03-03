class AddTitleAndDescriptionToStreamSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :stream_sessions, :title, :string
    add_column :stream_sessions, :description, :text
  end
end
