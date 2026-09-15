require "test_helper"

class StreamSessionSelectionTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Selection records")
    @creator = User.create!(email: "selection-creator@example.com", password: "password", role: :cast)
    @publisher = User.create!(email: "selection-publisher@example.com", password: "password", role: :store_admin)
    @assigned_cast = User.create!(email: "selection-assigned@example.com", password: "password", role: :cast)
    @booth = Booth.create!(store: @store, name: "Selection booth", status: :standby)
    BoothCast.create!(booth: @booth, cast_user: @assigned_cast)
    @session = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @creator,
      status: :live, started_at: 10.minutes.ago)
    @booth.update!(current_stream_session: @session)
  end

  test "本人の配信がなければnilを返し準備の作成者と担当者を固定しない" do
    [ nil, User.new, @creator, @publisher, @assigned_cast ].each do |user|
      assert_nil StreamSession.current_broadcast_for_selection(user)
    end
    assert_equal :not_started, @session.reload.publisher_recording_state
  end

  test "配信中と離席中では実配信者Yのブースと店舗だけを返す" do
    record_broadcast
    %i[live away].each do |status|
      @booth.update!(status: status)
      current = StreamSession.current_broadcast_for_selection(@publisher)
      assert_equal @session, current
      assert_equal @booth, current.booth
      assert_equal @store.id, current.store_id
      assert_equal [ current.id ], StreamSession.actually_broadcasting_by(@publisher).pluck(:id)
      assert_nil StreamSession.current_broadcast_for_selection(@creator)
      assert_nil StreamSession.current_broadcast_for_selection(@assigned_cast)
    end
  end

  test "初回の開始権と発行済みトークンだけでは本人配信にしない" do
    connection = build_connection
    assert_nil StreamSession.current_broadcast_for_selection(@publisher)
    connection.update!(ivs_participant_id: "participant", token_expires_at: 1.hour.from_now)
    assert_nil StreamSession.current_broadcast_for_selection(@publisher)
    assert_nil @session.reload.actual_publisher_user_id
  end

  test "再接続中は同じYを返し終了後の切断待ちは現在配信にしない" do
    record_broadcast
    connection = build_connection
    connection.update!(ivs_participant_id: "participant", token_expires_at: 1.hour.from_now,
      disconnect_requested_at: Time.current, disconnect_reason: "replace")
    assert_equal @session, StreamSession.current_broadcast_for_selection(@publisher)

    @session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session: nil, archived_at: Time.current)
    connection.update!(disconnect_reason: "end")
    assert_nil StreamSession.current_broadcast_for_selection(@publisher)
    assert_equal [ connection.id ], StreamPublisherConnection.disconnect_pending.pluck(:id)
    assert_equal @publisher.id, @session.reload.actual_publisher_user_id
  end

  test "本人に紐づく未終了記録の参照とブース状態の矛盾をnilにしない" do
    record_broadcast
    [ { current_stream_session: nil }, { status: :standby }, { status: :offline },
      { archived_at: Time.current } ].each do |attributes|
      @booth.update!(status: :live, current_stream_session: @session, archived_at: nil)
      @booth.update!(attributes)
      assert_raises(StreamSession::CurrentBroadcastInconsistent) do
        StreamSession.current_broadcast_for_selection(@publisher)
      end
    end
  end

  test "本人記録の終了状態と所属店舗の矛盾をnilにしない" do
    record_broadcast
    other_store = Store.create!(name: "Mismatched store")
    [ { status: :ended }, { ended_at: Time.current }, { store: other_store } ].each do |attributes|
      @session.update!(status: :live, ended_at: nil, store: @store)
      @session.update!(attributes)
      assert_raises(StreamSession::CurrentBroadcastInconsistent) do
        StreamSession.current_broadcast_for_selection(@publisher)
      end
    end
  end

  test "終了済みでも現在配信としてブースから参照されていれば不整合" do
    record_broadcast
    @session.update!(status: :ended, ended_at: Time.current)
    assert_empty StreamSession.actually_broadcasting_by(@publisher)
    assert_raises(StreamSession::CurrentBroadcastInconsistent) do
      StreamSession.current_broadcast_for_selection(@publisher)
    end
  end

  test "本人の整合する配信があっても別の未終了記録があれば固定先を推測しない" do
    record_broadcast
    other_booth = Booth.create!(store: @store, name: "Unfinished record")
    StreamSession.create!(booth: other_booth, store: @store, started_by_cast_user: @creator,
      status: :ended, started_at: 1.hour.ago, broadcast_started_at: 50.minutes.ago,
      actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: 50.minutes.ago)
    assert_equal [ @session.id ], StreamSession.actually_broadcasting_by(@publisher).pluck(:id)
    assert_raises(StreamSession::CurrentBroadcastInconsistent) do
      StreamSession.current_broadcast_for_selection(@publisher)
    end
  end

  test "他者や人物不明の不整合を準備作成者や担当者の現在配信にしない" do
    @booth.update!(status: :live)
    @session.update!(broadcast_started_at: 5.minutes.ago)
    [ @creator, @publisher, @assigned_cast ].each do |user|
      assert_nil StreamSession.current_broadcast_for_selection(user)
    end

    record_broadcast
    @booth.update!(current_stream_session: nil)
    assert_nil StreamSession.current_broadcast_for_selection(@creator)
    assert_nil StreamSession.current_broadcast_for_selection(@assigned_cast)
  end

  test "終了済みの旧履歴や不整合履歴を現在の本人配信へ広げない" do
    @session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session: nil)
    assert_nil StreamSession.current_broadcast_for_selection(@creator)

    @session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: 1.minute.from_now)
    assert_equal :inconsistent, @session.publisher_recording_state
    assert_nil StreamSession.current_broadcast_for_selection(@publisher)
  end

  test "別店舗の本人準備は現在の本人配信に混ざらず参照だけでは状態を更新しない" do
    record_broadcast
    other_store = Store.create!(name: "Other store")
    other_booth = Booth.create!(store: other_store, name: "Other preparation", status: :standby)
    other_session = StreamSession.create!(booth: other_booth, store: other_store,
      started_by_cast_user: @publisher, status: :live, started_at: Time.current)
    other_booth.update!(current_stream_session: other_session)
    before = [ @session.attributes, @booth.attributes, other_session.attributes, other_booth.attributes ]

    original_constructor = Aws::IVSRealTime::Client.method(:new)
    Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| raise "選択の本人判定でIVSへ照会しない" }
    assert_equal @session, StreamSession.current_broadcast_for_selection(@publisher)
    assert_equal before, [ @session.reload.attributes, @booth.reload.attributes,
      other_session.reload.attributes, other_booth.reload.attributes ]
  ensure
    Aws::IVSRealTime::Client.define_singleton_method(:new, original_constructor) if original_constructor
  end

  private

  def record_broadcast
    @session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: 5.minutes.ago)
    @booth.update!(status: :live)
  end

  def build_connection
    connection = StreamPublisherConnection.create!(stream_session: @session, booth: @booth, user: @publisher,
      request_id: SecureRandom.uuid, generation: 1, ivs_stage_arn: "selection-stage")
    @session.update!(current_publisher_connection: connection, publisher_generation: 1)
    connection
  end
end
