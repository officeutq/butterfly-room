class CreatePresences < ActiveRecord::Migration[8.1]
  def change
    create_table :presences do |t|
      t.references :stream_session, null: false, foreign_key: true
      t.references :customer_user, null: false, foreign_key: { to_table: :users }

      t.datetime :joined_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :left_at

      t.timestamps
    end

    add_index :presences, %i[stream_session_id left_at]
    add_index :presences, %i[stream_session_id last_seen_at]
    # 任意（入室ログを確実に残すなら）
    add_index :presences, %i[stream_session_id customer_user_id joined_at], unique: true
  end
end
