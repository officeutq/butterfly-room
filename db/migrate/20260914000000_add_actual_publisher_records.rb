class AddActualPublisherRecords < ActiveRecord::Migration[8.1]
  def change
    add_reference :stream_sessions, :actual_publisher_user, foreign_key: { to_table: :users }
    add_column :stream_sessions, :actual_publisher_source, :string
    add_column :stream_sessions, :actual_publisher_recorded_at, :datetime
    add_column :stream_sessions, :actual_publisher_evidence, :jsonb, null: false, default: {}
    add_column :stream_sessions, :publisher_generation, :bigint, null: false, default: 0
    add_index :stream_sessions, :actual_publisher_source
    add_index :stream_sessions, :actual_publisher_user_id, where: "ended_at IS NULL",
      name: :index_unended_sessions_on_actual_publisher

    add_check_constraint :stream_sessions, <<~SQL.squish, name: :stream_sessions_actual_publisher_record
      (actual_publisher_user_id IS NULL AND actual_publisher_source IS NULL AND actual_publisher_recorded_at IS NULL)
      OR (actual_publisher_user_id IS NOT NULL AND actual_publisher_source IS NOT NULL
          AND actual_publisher_recorded_at IS NOT NULL AND broadcast_started_at IS NOT NULL)
    SQL
    add_check_constraint :stream_sessions,
      "actual_publisher_source IN ('ivs_verified', 'legacy_creator_backfill', 'evidence_backfill')",
      name: :stream_sessions_actual_publisher_source
    add_check_constraint :stream_sessions, "publisher_generation >= 0", name: :stream_sessions_publisher_generation
    add_check_constraint :stream_sessions, "jsonb_typeof(actual_publisher_evidence) = 'object'",
      name: :stream_sessions_actual_publisher_evidence

    create_table :stream_publisher_connections do |t|
      t.uuid :request_id, null: false
      t.references :stream_session, null: false, foreign_key: true
      t.references :booth, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.bigint :generation, null: false
      t.string :ivs_stage_arn, null: false
      t.string :ivs_participant_id
      t.datetime :token_expires_at
      t.datetime :confirmed_at
      t.datetime :disconnect_requested_at
      t.string :disconnect_reason
      t.datetime :disconnected_at
      t.datetime :released_at
      t.integer :disconnect_attempts, null: false, default: 0
      t.string :last_disconnect_error
      t.datetime :next_disconnect_retry_at
      t.timestamps
    end

    add_index :stream_publisher_connections, :request_id, unique: true
    add_index :stream_publisher_connections, :user_id, unique: true, where: "released_at IS NULL",
      name: :index_unreleased_publisher_connections_on_user
    add_index :stream_publisher_connections, :stream_session_id, unique: true, where: "released_at IS NULL",
      name: :index_unreleased_publisher_connections_on_session
    add_index :stream_publisher_connections, [ :ivs_stage_arn, :ivs_participant_id ], unique: true,
      name: :index_publisher_connections_on_stage_and_participant
    add_index :stream_publisher_connections, :next_disconnect_retry_at,
      where: "disconnect_requested_at IS NOT NULL AND disconnected_at IS NULL",
      name: :index_pending_publisher_disconnect_retries

    add_check_constraint :stream_publisher_connections, "generation > 0", name: :publisher_connections_generation
    add_check_constraint :stream_publisher_connections, "disconnect_attempts >= 0", name: :publisher_connections_disconnect_attempts
    add_check_constraint :stream_publisher_connections,
      "(ivs_participant_id IS NULL) = (token_expires_at IS NULL)", name: :publisher_connections_participant_token
    add_check_constraint :stream_publisher_connections,
      "(disconnect_requested_at IS NULL) = (disconnect_reason IS NULL)", name: :publisher_connections_disconnect_request
    add_check_constraint :stream_publisher_connections,
      "disconnect_reason IN ('cancel', 'replace', 'end')", name: :publisher_connections_disconnect_reason

    add_reference :stream_sessions, :current_publisher_connection,
      foreign_key: { to_table: :stream_publisher_connections }
  end
end
