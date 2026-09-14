require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class StreamSessions::ConfirmPublisherServiceTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport

  setup { build_publisher_fixture }

  test "S03 Xの準備でYの成功を照合し人物 初回時刻 接続確認 ブース状態を一度だけ確定する" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      result = confirm_token(issued)
      assert_equal "confirmed", result[:state]
      assert_equal "live", result[:booth_status]
      assert_equal @publisher.id, result[:actual_publisher_user_id]
      session = @stream_session.reload
      assert_equal @creator.id, session.started_by_cast_user_id
      assert_equal "旧準備", session.title
      assert_equal @publisher.id, session.actual_publisher_user_id
      assert_equal "ivs_verified", session.actual_publisher_source
      assert_equal :recorded, session.publisher_recording_state
      assert_equal session.broadcast_started_at, session.actual_publisher_recorded_at
      assert_equal session.broadcast_started_at, session.current_publisher_connection.confirmed_at
      assert_equal session.broadcast_started_at, @booth.reload.last_online_at
      assert_equal({ "request_id" => issued[:request_id], "participant_id" => issued[:participant_id], "ivs_session_id" => "ivs-session" }, session.actual_publisher_evidence)
      saved = session.attributes
      ivs_request_count = @ivs_client.api_requests.size
      travel 1.minute do
        assert_equal result, confirm_token(issued)
      end
      assert_equal saved, session.reload.attributes
      assert_equal ivs_request_count, @ivs_client.api_requests.size
      assert_empty disconnect_requests
    end
  end

  test "S03 参加完了だけでは成功実績を作らない" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued, published: false)
      assert_unavailable { confirm_token(issued) }
      assert_unstarted
      assert_nil @stream_session.current_publisher_connection.confirmed_at
      assert_empty disconnect_requests
    end
  end

  test "S06 人物 役割 セッション属性の不一致と余分な配信者を拒否する" do
    with_publisher_client do
      issued = issue_token
      [ { "user_id" => @creator.id.to_s }, { "role" => "viewer" }, { "stream_session_id" => "other" } ].each do |attributes|
        stub_published_participant(issued, attributes: attributes)
        assert_unavailable { confirm_token(issued) }
        assert_unstarted
      end
      other = { participant_id: "unknown-participant", state: "CONNECTED", published: true,
        attributes: { "role" => "publisher", "stream_session_id" => @stream_session.id.to_s, "user_id" => @other_publisher.id.to_s } }
      stub_published_participant(issued, extra_participants: [ other ])
      assert_unavailable { confirm_token(issued) }
      assert_unstarted
      assert_empty disconnect_requests
    end
  end

  test "S06 同一セッションの通常の視聴者は成功確認を妨げない" do
    with_publisher_client do
      issued = issue_token
      viewer = { participant_id: "viewer", state: "CONNECTED", published: false,
        attributes: { "role" => "viewer", "stream_session_id" => @stream_session.id.to_s } }
      stub_published_participant(issued, extra_participants: [ viewer ])
      assert_equal "confirmed", confirm_token(issued)[:state]
    end
  end

  test "S06 IVS照会の失敗と対象参加者の欠落は確認不能にする" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      @ivs_client.stub_responses(:get_participant, "AccessDeniedException")
      assert_unavailable { confirm_token(issued) }
      assert_unstarted
      @ivs_client.stub_responses(:list_participants, { participants: [] })
      assert_unavailable { confirm_token(issued) }
      assert_unstarted
    end
  end

  test "S05 最後のブース保存が失敗しても人物と時刻だけが残らず同じ要求を取消して復帰する" do
    callback = ->(record) { raise ActiveRecord::RecordInvalid, record if record.live? }
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      Booth.set_callback(:update, :after, callback)
      assert_raises(ActiveRecord::RecordInvalid) { confirm_token(issued) }
      assert_unstarted
      assert_nil @stream_session.current_publisher_connection.confirmed_at
      result = cancel_token(issued)
      assert_equal "cancelled", result[:state]
      assert_equal [ { stage_arn: @booth.ivs_stage_arn, participant_id: issued[:participant_id] } ], disconnect_requests
      assert_unstarted
    end
  ensure
    Booth.skip_callback(:update, :after, callback)
  end

  test "R03 取消が先なら古い成功通知を拒否し成功が先なら取消で消さない" do
    with_publisher_client do
      issued = issue_token
      cancel_token(issued)
      error = assert_raises(StreamSessions::PublisherControl::Error) { confirm_token(issued) }
      assert_equal "stale_publisher_request", error.code
      assert_unstarted
      next_issued = issue_token(generation: @stream_session.publisher_generation)
      stub_published_participant(next_issued)
      confirmed = confirm_token(next_issued)
      assert_equal confirmed, cancel_token(next_issued)
      assert_equal 1, disconnect_requests.size
      assert_equal @publisher.id, @stream_session.reload.actual_publisher_user_id
      error = assert_raises(StreamSessions::PublisherControl::Error) { confirm_token(issued) }
      assert_equal "stale_publisher_request", error.code
      assert_equal next_issued[:request_id], @stream_session.reload.current_publisher_connection.request_id
    end
  end

  test "P05 成功通知直前の閉鎖と権限喪失を再確認する" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      @booth.update!(archived_at: Time.current)
      error = assert_raises(StreamSessions::PublisherControl::Error) { confirm_token(issued) }
      assert_equal "not_joinable", error.code
      @booth.update!(archived_at: nil)
      StoreMembership.where(store: @store, user: @publisher).delete_all
      error = assert_raises(StreamSessions::PublisherControl::Error) { confirm_token(issued) }
      assert_equal "forbidden", error.code
      assert_unstarted
    end
  end

  private

  def assert_unavailable(&block)
    error = assert_raises(StreamSessions::PublisherControl::Error, &block)
    assert_equal "publisher_state_unavailable", error.code
    assert_equal :service_unavailable, error.status
  end

  def assert_unstarted
    assert_nil @stream_session.reload.actual_publisher_user_id
    assert_nil @stream_session.broadcast_started_at
    assert_equal @creator.id, @stream_session.started_by_cast_user_id
    assert @booth.reload.standby?
  end
end
