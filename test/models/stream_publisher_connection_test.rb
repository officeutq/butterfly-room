require "test_helper"

class StreamPublisherConnectionTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Publisher connections")
    @publisher = User.create!(email: "publisher_connection@example.com", password: "password", role: :cast)
    @other_user = User.create!(email: "other_connection@example.com", password: "password", role: :cast)
    @booth = Booth.create!(store: @store, name: "Connection booth", status: :standby)
    @session = create_session(@booth)
    @booth.update!(current_stream_session: @session)
  end

  test "発行前の開始権だけでは実配信者や初回時刻を記録しない" do
    connection = StreamPublisherConnection.create!(connection_attributes)
    @session.update!(current_publisher_connection: connection, publisher_generation: connection.generation)

    assert_equal [ connection.id ], StreamPublisherConnection.unreleased.pluck(:id)
    assert_empty StreamPublisherConnection.disconnect_pending
    assert_nil connection.ivs_participant_id
    assert_nil connection.token_expires_at
    assert_nil @session.reload.actual_publisher_user
    assert_nil @session.broadcast_started_at
    assert_equal :not_started, @session.publisher_recording_state
    assert_empty StreamSession.actually_broadcasting_by(@publisher)
  end

  test "同じ人の別ブース開始と同じセッションの別人開始をDBで拒否する" do
    first = StreamPublisherConnection.create!(connection_attributes)
    other_booth = Booth.create!(store: @store, name: "Other connection booth")
    other_session = create_session(other_booth)
    assert_unique_conflict(connection_attributes(stream_session: other_session, booth: other_booth))
    assert_unique_conflict(connection_attributes(user: @other_user))

    first.update!(released_at: Time.current)
    replacement = StreamPublisherConnection.create!(connection_attributes(generation: 2))
    assert_equal [ replacement.id ], StreamPublisherConnection.unreleased.pluck(:id)
    assert StreamPublisherConnection.exists?(first.id)
  end

  test "同じ要求IDと同じStage内参加者IDは解放後も再利用できない" do
    first = StreamPublisherConnection.create!(connection_attributes(ivs_participant_id: "old-participant",
      token_expires_at: 1.hour.from_now, released_at: Time.current))
    assert_unique_conflict(connection_attributes(request_id: first.request_id))
    assert_unique_conflict(connection_attributes(ivs_participant_id: first.ivs_participant_id,
      token_expires_at: 1.hour.from_now))
    assert StreamPublisherConnection.create!(connection_attributes(ivs_stage_arn: "other-stage",
      ivs_participant_id: first.ivs_participant_id, token_expires_at: 1.hour.from_now)).persisted?
  end

  test "終了 閉鎖 退会後も切断未完了の開始権を検索できる" do
    connection = StreamPublisherConnection.create!(connection_attributes(ivs_participant_id: "pending-participant",
      token_expires_at: 1.hour.ago, disconnect_requested_at: Time.current, disconnect_reason: "end",
      disconnect_attempts: 1, last_disconnect_error: "ServiceUnavailableException", next_disconnect_retry_at: 5.seconds.from_now))
    @session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session: nil, archived_at: Time.current)
    @publisher.update!(deleted_at: Time.current)

    assert_equal [ connection.id ], StreamPublisherConnection.unreleased.pluck(:id)
    assert_equal [ connection.id ], StreamPublisherConnection.disconnect_pending.pluck(:id)
    assert_unique_conflict(connection_attributes)
    connection.update!(disconnected_at: Time.current, released_at: Time.current)
    assert_empty StreamPublisherConnection.disconnect_pending
    assert_empty StreamPublisherConnection.unreleased
    assert StreamPublisherConnection.exists?(connection.id)
  end

  test "新しい接続があっても切断待ち検索は保存された旧参加者を指す" do
    old = StreamPublisherConnection.create!(connection_attributes(ivs_participant_id: "old-participant",
      token_expires_at: 1.hour.from_now, disconnect_requested_at: Time.current, disconnect_reason: "replace",
      disconnected_at: Time.current, released_at: Time.current))
    current = StreamPublisherConnection.create!(connection_attributes(generation: 2,
      ivs_participant_id: "new-participant", token_expires_at: 1.hour.from_now))
    @session.update!(current_publisher_connection: current, publisher_generation: 2)
    assert_empty StreamPublisherConnection.disconnect_pending
    assert_equal "old-participant", old.reload.ivs_participant_id
    assert_equal current, @session.reload.current_publisher_connection
  end

  test "モデルで別ブースや別セッションの接続参照を拒否する" do
    other_booth = Booth.create!(store: @store, name: "Mismatch")
    invalid = StreamPublisherConnection.new(connection_attributes(booth: other_booth))
    assert_not invalid.valid?
    assert_includes invalid.errors.attribute_names, :booth
    other_session = create_session(other_booth)
    connection = StreamPublisherConnection.create!(connection_attributes(stream_session: other_session, booth: other_booth))
    @session.current_publisher_connection = connection
    assert_not @session.valid?
    assert_includes @session.errors.attribute_names, :current_publisher_connection
  end

  test "参加者IDと期限および切断要求と理由を組で保存する" do
    [ { ivs_participant_id: "partial" }, { token_expires_at: Time.current },
      { disconnect_requested_at: Time.current }, { disconnect_reason: "end" },
      { disconnect_requested_at: Time.current, disconnect_reason: "unknown" },
      { generation: 0 }, { disconnect_attempts: -1 } ].each do |attributes|
      connection = StreamPublisherConnection.new(connection_attributes(**attributes))
      assert_not connection.valid?, attributes.inspect
      assert_raises(ActiveRecord::StatementInvalid) do
        StreamPublisherConnection.transaction(requires_new: true) { connection.save!(validate: false) }
      end
    end
  end

  test "接続の履歴削除と親セッションの連鎖削除を拒否する" do
    connection = StreamPublisherConnection.create!(connection_attributes(released_at: Time.current))
    assert_not connection.destroy
    @booth.update!(current_stream_session: nil)
    assert_not @session.destroy
    assert StreamPublisherConnection.exists?(connection.id)
    assert StreamSession.exists?(@session.id)
  end

  test "接続対象と現在接続には実在する外部キーが必要" do
    connection = StreamPublisherConnection.create!(connection_attributes)
    [ :stream_session_id, :booth_id, :user_id ].each do |column|
      assert_raises(ActiveRecord::InvalidForeignKey) do
        StreamPublisherConnection.transaction(requires_new: true) { connection.update_columns(column => -1) }
      end
      connection.reload
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      StreamSession.transaction(requires_new: true) { @session.update_columns(current_publisher_connection_id: -1) }
    end
  end

  private

  def create_session(booth)
    StreamSession.create!(booth: booth, store: @store, started_by_cast_user: @publisher,
      started_at: Time.current, status: :live)
  end

  def connection_attributes(**overrides)
    { request_id: SecureRandom.uuid, stream_session: @session, booth: @booth, user: @publisher,
      generation: 1, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/model-test" }.merge(overrides)
  end

  def assert_unique_conflict(attributes)
    assert_raises(ActiveRecord::RecordNotUnique) do
      StreamPublisherConnection.transaction(requires_new: true) do
        StreamPublisherConnection.new(attributes).save!(validate: false)
      end
    end
  end
end
