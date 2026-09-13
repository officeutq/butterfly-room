class RecordStreamBroadcasters < ActiveRecord::Migration[8.1]
  def change
    # 旧方式は有効期間12時間のトークンを発行する。移行は旧発行口停止後に実行する。
    add_column :booths, :publisher_blocked_until, :datetime, default: -> { "CURRENT_TIMESTAMP + INTERVAL '12 hours 1 minute'" }
    change_column_default :booths, :publisher_blocked_until, from: -> { "CURRENT_TIMESTAMP + INTERVAL '12 hours 1 minute'" }, to: nil
    add_reference :stream_sessions, :broadcast_started_by_user, foreign_key: { to_table: :users }
    add_column :stream_sessions, :broadcast_identity_source, :string
    add_column :stream_sessions, :broadcast_identity_evidence, :jsonb, null: false, default: {}
    # 旧クライアントが作成したセッションは自動で新方式へ読み替えない。
    add_column :stream_sessions, :publisher_protocol, :integer

    create_table :stream_publish_attempts do |t|
      t.references :stream_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :request_id, null: false
      t.string :participant_id
      t.datetime :expires_at, null: false
      t.datetime :cancelled_at
      t.datetime :retired_at
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :stream_publish_attempts, :request_id, unique: true
    add_index :stream_publish_attempts, :user_id, unique: true, where: "retired_at IS NULL", name: "one_open_publish_attempt_per_user"
    add_index :stream_publish_attempts, :stream_session_id, unique: true, where: "retired_at IS NULL", name: "one_open_publish_attempt_per_session"
    change_column_null :comments, :user_id, true
  end
end
