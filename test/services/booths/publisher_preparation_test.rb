require "test_helper"

class Booths::PublisherPreparationTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Publisher preparation", published: true)
    @creator = User.create!(email: "preparation_creator@example.com", password: "password", role: :cast)
    @publisher = User.create!(email: "preparation_publisher@example.com", password: "password", role: :store_admin)
    @outsider = User.create!(email: "preparation_outsider@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @publisher, membership_role: :admin)
    @booth = Booth.create!(store: @store, name: "Prepared booth", status: :standby,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/preparation")
    BoothCast.create!(booth: @booth, cast_user: @creator)
    @session = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @creator,
      started_at: 10.minutes.ago, status: :live, title: "Xの旧準備", ivs_stage_arn: @booth.ivs_stage_arn)
    @booth.update!(current_stream_session: @session)
    @client = Aws::IVSRealTime::Client.new(stub_responses: true)
    @client.stub_responses(:get_stage, ->(context) { { stage: { arn: context.params[:arn] } } })
  end

  test "P02 M01 旧準備と新しい未発行準備を権限Yが同じIDで再利用する" do
    new_control do
      before = @session.attributes
      assert_no_difference "StreamSession.count" do
        result = enter(@booth, @publisher)
        assert_equal :redirect_live, result.action
        assert_equal @session.id, result.stream_session.id
      end
      assert_equal before, @session.reload.attributes
      assert_equal 2, @client.api_requests.size
      assert_nil @session.actual_publisher_user
    end
  end

  test "P01 P03 別ブースの準備だけでは本人配信中とせず準備要求時だけ作成する" do
    other = Booth.create!(store: @store, name: "New preparation", status: :offline, ivs_stage_arn: "other-stage")
    @session.update!(started_by_cast_user: @publisher)
    before = @session.attributes
    new_control do
      assert_difference "StreamSession.count", 1 do
        result = enter(other, @publisher)
        assert_equal :redirect_live, result.action
        assert_equal @publisher.id, result.stream_session.started_by_cast_user_id
        assert_nil result.stream_session.actual_publisher_user_id
      end
      assert_equal before, @session.reload.attributes
      assert @client.api_requests.all? { |r| r[:params][:arn] == other.ivs_stage_arn }
    end
  end

  test "P04 本人配信中と離席中はYだけが復帰しXは開始できない" do
    record_broadcast
    new_control do
      %i[live away].each do |state|
        @booth.update!(status: state)
        assert_equal :redirect_live, enter(@booth, @publisher).action
        error = assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @creator) }
        assert_equal "publisher_in_use", error.code
        assert_equal :conflict, error.status
      end
      assert_empty @client.api_requests
      assert_equal @publisher, @session.reload.actual_publisher_user
    end
  end

  test "P04 配信中Yの別準備への入場も新規作成も拒否する" do
    record_broadcast
    other = Booth.create!(store: @store, name: "Other booth", status: :offline, ivs_stage_arn: "other-stage")
    new_control do
      assert_no_difference "StreamSession.count" do
        assert_equal :already_live_elsewhere, enter(other, @publisher).action
      end
      other_session = StreamSession.create!(booth: other, store: @store, started_by_cast_user: @creator,
        started_at: Time.current, status: :live, ivs_stage_arn: other.ivs_stage_arn)
      other.update!(status: :standby, current_stream_session: other_session)
      error = assert_raises(StreamSessions::PublisherControl::Error) { enter(other, @publisher) }
      assert_equal "publisher_in_use", error.code
      assert_empty @client.api_requests
      assert_nil other_session.reload.actual_publisher_user
    end
  end

  test "P05 権限なし 閉鎖済み 終了済み 別ブース参照を拒否して元の値を保持する" do
    new_control do
      assert_raises(Booths::EnterAsCastService::NotAuthorized) { enter(@booth, @outsider) }
      @booth.update!(archived_at: Time.current)
      assert_raises(ActiveRecord::RecordNotFound) { enter(@booth, @publisher) }
      @booth.update!(archived_at: nil)
      @session.update!(status: :ended, ended_at: Time.current)
      error = assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @publisher) }
      assert_equal "not_joinable", error.code
      @session.update!(status: :live, ended_at: nil)
      other = Booth.create!(store: @store, name: "Mismatched", status: :standby, current_stream_session: @session)
      assert_raises(StreamSessions::PublisherControl::Error) { enter(other, @publisher) }
      assert_equal @session.id, @booth.reload.current_stream_session_id
      assert @booth.standby?
      assert_empty @client.api_requests
    end
  end

  test "S06 調査不能なら旧準備を保持し同じ対象の再確認で復帰できる" do
    new_control do
      before = @session.attributes
      @client.stub_responses(:get_stage, "AccessDeniedException")
      error = assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @publisher) }
      assert_equal "publisher_state_unavailable", error.code
      assert_equal :service_unavailable, error.status
      assert_equal before, @session.reload.attributes
      assert_equal @session.id, @booth.reload.current_stream_session_id
      @client.stub_responses(:get_stage, { stage: { arn: @booth.ivs_stage_arn } })
      assert_equal :redirect_live, enter(@booth, @publisher).action
      assert_equal before, @session.reload.attributes
    end
  end

  test "S06 DBが空きでもStage確認失敗では新しい準備を残さない" do
    other = Booth.create!(store: @store, name: "Offline booth", status: :offline, ivs_stage_arn: "other-stage")
    new_control do
      @client.stub_responses(:get_stage, "ResourceNotFoundException")
      assert_no_difference "StreamSession.count" do
        assert_raises(StreamSessions::PublisherControl::Error) { enter(other, @publisher) }
      end
      assert other.reload.offline?
      assert_nil other.current_stream_session_id
    end
  end

  test "S06 未記録の配信とStage矛盾を未開始の準備へ修復しない" do
    new_control do
      @booth.update!(status: :live)
      assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @publisher) }
      assert_nil @session.reload.actual_publisher_user
      assert @booth.reload.live?
      @booth.update!(status: :standby, ivs_stage_arn: "changed-stage")
      error = assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @publisher) }
      assert_equal "stage_mismatch", error.code
      assert_empty @client.api_requests
    end
  end

  test "S06 他人や属性不明や別セッションの外部接続は推測で引き継がない" do
    new_control do
      [ {}, { "role" => "publisher", "user_id" => @creator.id.to_s, "stream_session_id" => @session.id.to_s },
        { "role" => "viewer", "stream_session_id" => "other-session" } ].each do |attributes|
        stub_connected_participant(attributes)
        error = assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @publisher) }
        assert_equal "publisher_state_unavailable", error.code
        assert_nil @session.reload.actual_publisher_user
      end
      assert_not_includes @client.api_requests.map { |r| r[:operation_name] }, :disconnect_participant
    end
  end

  test "自分の保存済み開始要求の接続は同じ準備の回復画面を開ける" do
    connection = StreamPublisherConnection.create!(stream_session: @session, booth: @booth, user: @publisher,
      request_id: SecureRandom.uuid, generation: 1, ivs_stage_arn: @booth.ivs_stage_arn,
      ivs_participant_id: "connected", token_expires_at: 1.hour.from_now)
    @session.update!(publisher_generation: 1, current_publisher_connection: connection)
    stub_connected_participant("role" => "publisher", "stream_session_id" => @session.id.to_s, "user_id" => @publisher.id.to_s)
    new_control do
      assert_equal :redirect_live, enter(@booth, @publisher).action
      assert_nil @session.reload.actual_publisher_user
      assert_raises(StreamSessions::PublisherControl::Error) { enter(@booth, @creator) }
    end
  end

  test "有効化しない間は既存入口を維持してIVSの追加照会をしない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => nil) do
      assert_equal :redirect_live, enter(@booth, @publisher).action
      assert_empty @client.api_requests
    end
  end

  private

  def new_control
    original_constructor = Aws::IVSRealTime::Client.method(:new)
    client = @client
    Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| client }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      yield
    end
  ensure
    Aws::IVSRealTime::Client.define_singleton_method(:new, original_constructor)
  end

  def enter(booth, actor)
    Booths::EnterAsCastService.new(booth: booth, actor: actor).call
  end

  def record_broadcast
    @session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: 5.minutes.ago)
    @booth.update!(status: :live)
  end

  def stub_connected_participant(attributes)
    @client.stub_responses(:get_stage, { stage: { arn: @booth.ivs_stage_arn, active_session_id: "st-1234567890123" } })
    @client.stub_responses(:list_participants, { participants: [ { participant_id: "connected", state: "CONNECTED", published: false } ] })
    @client.stub_responses(:get_participant, { participant: { participant_id: "connected", state: "CONNECTED", published: false, attributes: attributes } })
  end
end
