require "test_helper"

class StreamSessionTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Publisher records")
    @creator = User.create!(email: "publisher_creator@example.com", password: "password", role: :cast)
    @publisher = User.create!(email: "actual_publisher@example.com", password: "password", role: :store_admin)
    @assigned_cast = User.create!(email: "publisher_assigned@example.com", password: "password", role: :cast)
    @booth = Booth.create!(store: @store, name: "Publisher booth", status: :standby)
    BoothCast.create!(booth: @booth, cast_user: @assigned_cast)
    @session = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @creator,
      status: :live, started_at: 10.minutes.ago, title: "Existing preparation")
    @booth.update!(current_stream_session: @session)
  end

  test "title length max 64" do
    s = StreamSession.new(title: "a" * 65)
    s.validate
    assert_includes s.errors.details[:title], { error: :too_long, count: 64 }
  end

  test "旧準備は作成者も担当者も実配信者に読み替えず値を保持する" do
    before = @session.attributes
    assert_equal :not_started, @session.publisher_recording_state
    assert_nil @session.actual_publisher_user
    assert_nil @booth.actual_publisher_user
    assert_not @session.actual_publisher?(@creator)
    assert_not @session.actual_publisher?(nil)
    assert_not @session.actual_publisher?(User.new)
    assert_empty StreamSession.actually_broadcasting_by(@creator)
    assert_empty StreamSession.actually_broadcasting_by(nil)
    assert_equal before, @session.reload.attributes
    assert_equal 0, @session.publisher_generation
    assert_equal({}, @session.actual_publisher_evidence)
  end

  test "X Y Zが異なる配信と離席ではYだけを本人配信中として参照する" do
    record_broadcast
    %i[live away].each do |status|
      @booth.update!(status: status)
      assert_equal :recorded, @session.publisher_recording_state
      assert_equal @publisher, @session.actual_publisher_user
      assert_equal @publisher, @booth.actual_publisher_user
      assert @session.actual_publisher?(@publisher)
      assert_not @session.actual_publisher?(@creator)
      assert_not @session.actual_publisher?(@assigned_cast)
      assert_equal [ @session.id ], StreamSession.actually_broadcasting_by(@publisher).pluck(:id)
      assert_empty StreamSession.actually_broadcasting_by(@creator)
      assert_empty StreamSession.actually_broadcasting_by(@assigned_cast)
    end
    assert_equal @creator, @session.reload.started_by_cast_user
    assert_equal @assigned_cast, @booth.primary_cast_user
  end

  test "別店舗の準備のみは本人配信中の結果へ混ざらない" do
    record_broadcast
    other_store = Store.create!(name: "Other store")
    other_booth = Booth.create!(store: other_store, name: "Other preparation", status: :standby)
    preparation = StreamSession.create!(booth: other_booth, store: other_store,
      started_by_cast_user: @publisher, status: :live, started_at: Time.current)
    other_booth.update!(current_stream_session: preparation)

    assert_equal :not_started, preparation.publisher_recording_state
    assert_equal [ @session.id ], StreamSession.actually_broadcasting_by(@publisher).pluck(:id)
    assert_nil preparation.reload.actual_publisher_user_id
  end

  test "現在参照 状態 時刻の矛盾を配信中や空きとみなさない" do
    record_broadcast
    @booth.update!(current_stream_session: nil)
    assert_equal :inconsistent, @session.publisher_recording_state
    assert_nil @booth.actual_publisher_user
    assert_empty StreamSession.actually_broadcasting_by(@publisher)

    @booth.update!(current_stream_session: @session, status: :standby)
    assert_equal :inconsistent, @session.publisher_recording_state
    assert_nil @booth.actual_publisher_user
    assert_empty StreamSession.actually_broadcasting_by(@publisher)

    @booth.update!(status: :live)
    @session.update!(ended_at: Time.current)
    assert_equal :inconsistent, @session.publisher_recording_state
    assert_nil @booth.actual_publisher_user
    assert_empty StreamSession.actually_broadcasting_by(@publisher)
  end

  test "未記録の配信中と離席中は不整合であり準備として扱わない" do
    %i[live away].each do |status|
      @booth.update!(status: status)
      assert_equal :inconsistent, @session.publisher_recording_state
      assert_nil @booth.actual_publisher_user
      assert_empty StreamSession.actually_broadcasting_by(@creator)
    end
    @session.update!(broadcast_started_at: 5.minutes.ago)
    assert_equal :inconsistent, @session.publisher_recording_state
  end

  test "記録済みの履歴は閉鎖や退会や担当の変更後もYを保持する" do
    record_broadcast
    recorded = @session.attributes.slice("actual_publisher_user_id", "actual_publisher_source",
      "actual_publisher_recorded_at", "actual_publisher_evidence", "broadcast_started_at")
    @session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session: nil, archived_at: Time.current)
    @booth.booth_casts.destroy_all
    @publisher.update!(deleted_at: Time.current)

    assert_equal :recorded, @session.publisher_recording_state
    assert_equal @publisher, @session.actual_publisher_user
    assert @session.actual_publisher?(@publisher)
    assert_nil @booth.actual_publisher_user
    assert_empty StreamSession.actually_broadcasting_by(@publisher)
    assert_equal recorded, @session.reload.attributes.slice(*recorded.keys)
  end

  test "旧終了履歴は開始時刻がなくても未開始と推定しない" do
    @session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session: nil)
    assert_equal :unknown, @session.publisher_recording_state
    @session.update!(broadcast_started_at: 5.minutes.ago)
    assert_equal :unknown, @session.publisher_recording_state
    assert_nil @session.actual_publisher_user
    assert_empty StreamSession.actually_broadcasting_by(@creator)
  end

  test "履歴の終了時刻が欠落または開始より前なら不整合" do
    record_broadcast
    @session.update!(status: :ended)
    assert_equal :inconsistent, @session.publisher_recording_state
    @session.update!(ended_at: @session.broadcast_started_at - 1.second)
    assert_equal :inconsistent, @session.publisher_recording_state
  end

  test "人物 由来 記録時刻 開始時刻を組で保存し補完由来も区別できる" do
    @session.actual_publisher_user = @publisher
    assert_not @session.valid?
    @session.actual_publisher_recorded_at = Time.current
    @session.actual_publisher_source = "ivs_verified"
    assert_not @session.valid?
    @session.broadcast_started_at = Time.current
    assert @session.valid?
    StreamSession::ACTUAL_PUBLISHER_SOURCES.each do |source|
      @session.update!(actual_publisher_source: source)
      assert_equal source, @session.reload.actual_publisher_source
    end
    @session.actual_publisher_source = "guessed"
    assert_not @session.valid?
    @session.actual_publisher_source = "evidence_backfill"
    @session.actual_publisher_evidence = []
    assert_not @session.valid?
  end

  test "DBへの直接更新でも不完全な人物記録と不正な世代を拒否する" do
    [ { actual_publisher_user_id: @publisher.id }, { actual_publisher_source: "ivs_verified" },
      { actual_publisher_recorded_at: Time.current }, { publisher_generation: -1 },
      { actual_publisher_evidence: [] } ].each do |attributes|
      assert_raises(ActiveRecord::StatementInvalid) do
        StreamSession.transaction(requires_new: true) { @session.update_columns(attributes) }
      end
      @session.reload
    end
    record_broadcast
    [ { actual_publisher_source: "guessed" }, { broadcast_started_at: nil } ].each do |attributes|
      assert_raises(ActiveRecord::StatementInvalid) do
        StreamSession.transaction(requires_new: true) { @session.update_columns(attributes) }
      end
      @session.reload
    end
  end

  test "実配信者の外部キーは人物の物理削除を拒否する" do
    record_broadcast
    assert_raises(ActiveRecord::InvalidForeignKey) do
      User.transaction(requires_new: true) { @publisher.delete }
    end
    assert_equal @publisher.id, @session.reload.actual_publisher_user_id
  end

  private

  def record_broadcast
    @session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: 5.minutes.ago,
      actual_publisher_evidence: { "request_id" => SecureRandom.uuid })
    @booth.update!(status: :live)
  end
end
