class CreateStreamSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :stream_sessions do |t|
      t.references :booth, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.integer :status, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.references :started_by_cast_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :stream_sessions, %i[booth_id started_at]
    add_index :stream_sessions, %i[store_id started_at]
    add_index :stream_sessions, :ended_at
  end
end
