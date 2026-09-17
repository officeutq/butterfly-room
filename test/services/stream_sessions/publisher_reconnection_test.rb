require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class StreamSessions::PublisherReconnectionTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport

  setup { build_publisher_fixture }

  test "R01 R02 離席中の本人が旧接続を切断して同じ実績へ復帰する" do
    with_publisher_client do
      first = begin_broadcast
      StreamSessions::StatusService.new(booth: @booth, actor: @publisher, to_status: :away,
        stream_session_id: @stream_session.id, request_id: first[:request_id], generation: first[:generation]).call
      assert @booth.reload.away?
      original = historical_values
      travel 1.minute do
        second = issue_token(generation: 1)
        assert_equal 2, second[:generation]
        refute_equal first[:participant_id], second[:participant_id]
        assert_equal original, historical_values
        assert @booth.reload.away?
        previous = StreamPublisherConnection.find_by!(request_id: first[:request_id])
        assert_equal "replace", previous.disconnect_reason
        assert previous.disconnected_at
        assert previous.released_at
        assert_equal 1, StreamPublisherConnection.unreleased.where(user: @publisher).count
        assert_equal second[:request_id], @stream_session.reload.current_publisher_connection.request_id
        stub_published_participant(second)
        assert_equal "confirmed", confirm_token(second)[:state]
        assert @booth.reload.live?
        assert_equal original, historical_values
        assert_operator @stream_session.current_publisher_connection.confirmed_at, :>, @stream_session.broadcast_started_at
      end
      assert_equal [ { stage_arn: @booth.ivs_stage_arn, participant_id: first[:participant_id] } ], disconnect_requests
    end
  end

  test "R02 Xや別人にYの再接続を引き継がせない" do
    with_publisher_client do
      begin_broadcast
      original = historical_values
      [ @creator, @other_publisher ].each do |actor|
        error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(actor: actor, generation: 1) }
        assert_equal "publisher_in_use", error.code
      end
      assert_equal original, historical_values
      assert_equal 1, issued_count
      assert_empty disconnect_requests
    end
  end

  test "R02 外部に未知の配信者がいれば保存済み旧接続も切断しない" do
    with_publisher_client do
      first = begin_broadcast
      other = { participant_id: "unknown", state: "CONNECTED", published: true,
        attributes: { "role" => "publisher", "stream_session_id" => @stream_session.id.to_s, "user_id" => @publisher.id.to_s } }
      stub_published_participant(first, extra_participants: [ other ])
      error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(generation: 1) }
      assert_equal "publisher_state_unavailable", error.code
      assert_equal 1, issued_count
      assert_empty disconnect_requests
    end
  end

  test "R02 切断失敗時は旧開始権と実績を維持し同じ世代から再試行できる" do
    with_publisher_client do
      first = begin_broadcast
      original = historical_values
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(generation: 1) }
      assert_equal "publisher_disconnect_pending", error.code
      assert_equal 1, issued_count
      assert_equal original, historical_values
      previous = @stream_session.reload.current_publisher_connection
      assert_equal first[:request_id], previous.request_id
      assert_nil previous.released_at
      assert previous.disconnect_requested_at
      assert_equal 1, previous.disconnect_attempts
      @ivs_client.stub_responses(:disconnect_participant, {})
      travel_to(previous.next_disconnect_retry_at + 1.second) do
        assert_equal "issued", issue_token(generation: 1)[:state]
      end
      assert_equal 2, disconnect_requests.size
      assert_equal original, historical_values
    end
  end

  test "R02 切断後の発行失敗とDB保存失敗でも切断済み記録を戻さず同じ実績へ再発行する" do
    callback = ->(record) { raise ActiveRecord::RecordInvalid, record if record.generation > 1 }
    with_publisher_client do
      first = begin_broadcast
      original = historical_values
      StreamPublisherConnection.set_callback(:update, :after, callback)
      assert_raises(ActiveRecord::RecordInvalid) { issue_token(generation: 1) }
      StreamPublisherConnection.skip_callback(:update, :after, callback)
      @ivs_client.stub_responses(:create_participant_token, "AccessDeniedException")
      assert_raises(StreamSessions::PublisherControl::Error) { issue_token(generation: 1) }
      assert_equal 1, @stream_session.reload.publisher_generation
      assert_equal first[:request_id], @stream_session.current_publisher_connection.request_id
      assert @stream_session.current_publisher_connection.released_at
      assert_equal 1, @stream_session.stream_publisher_connections.count
      assert_equal original, historical_values
      @ivs_client.stub_responses(:create_participant_token, { participant_token: {
        token: "retry-token", participant_id: "retry-participant", expiration_time: 1.hour.from_now } })
      second = issue_token(generation: 1)
      assert_equal "issued", second[:state]
      assert_equal [ first[:participant_id] ], disconnect_requests.pluck(:participant_id)
      assert_equal original, historical_values
    end
  ensure
    StreamPublisherConnection.skip_callback(:update, :after, callback, raise: false)
  end

  test "R02 復帰の参加失敗を本人が取消しても実績は消えず同じセッションへ再発行できる" do
    with_publisher_client do
      begin_broadcast
      original = historical_values
      second = issue_token(generation: 1)
      error = assert_raises(StreamSessions::PublisherControl::Error) { cancel_token(second, actor: @other_publisher) }
      assert_equal "forbidden", error.code
      assert_equal "cancelled", cancel_token(second)[:state]
      assert_equal original, historical_values
      assert @booth.reload.live?
      assert_nil @stream_session.reload.current_publisher_connection
      @ivs_client.stub_responses(:get_stage, { stage: { arn: @booth.ivs_stage_arn } })
      third = issue_token(generation: 3)
      assert_equal 4, third[:generation]
      stub_published_participant(third)
      confirm_token(third)
      assert_equal original, historical_values
    end
  end

  test "R03 旧成功 取消 状態変更は新しい接続と実績に影響しない" do
    with_publisher_client do
      first = begin_broadcast
      second = issue_token(generation: 1)
      stub_published_participant(second)
      confirm_token(second)
      original = historical_values
      [ -> { confirm_token(first) }, -> { cancel_token(first) },
        -> { StreamSessions::StatusService.new(booth: @booth, actor: @publisher, to_status: :away,
          stream_session_id: @stream_session.id, request_id: first[:request_id], generation: first[:generation]).call } ].each do |operation|
        error = assert_raises(StreamSessions::PublisherControl::Error, &operation)
        assert_equal "stale_publisher_request", error.code
      end
      assert @booth.reload.live?
      assert_equal second[:request_id], @stream_session.reload.current_publisher_connection.request_id
      assert_equal original, historical_values
      previous = StreamPublisherConnection.find_by!(request_id: first[:request_id])
      Ivs::DisconnectPublisherConnectionService.new(connection_id: previous.id).call
      assert_equal [ first[:participant_id] ], disconnect_requests.pluck(:participant_id)
      assert_equal 2, issued_count
    end
  end

  private

  def begin_broadcast
    result = issue_token
    stub_published_participant(result)
    confirm_token(result)
    result
  end

  def historical_values
    @stream_session.reload.attributes.slice("id", "started_by_cast_user_id", "actual_publisher_user_id", "actual_publisher_source",
      "actual_publisher_recorded_at", "actual_publisher_evidence", "broadcast_started_at", "title", "started_at")
  end
end
