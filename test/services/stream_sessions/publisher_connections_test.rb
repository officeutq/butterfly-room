require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class StreamSessions::PublisherConnectionsTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport

  setup { build_publisher_fixture }

  test "S01 旧準備のXを保持し参加者IDを保存してからYにtokenを返す" do
    with_publisher_client do
      result = issue_token
      connection = @stream_session.reload.current_publisher_connection
      assert_equal @publisher, connection.user
      assert_equal result[:request_id], connection.request_id
      assert_equal result[:participant_id], connection.ivs_participant_id
      assert_equal result[:expires_at], connection.token_expires_at
      assert_equal "issued", result[:state]
      assert_equal 1, result[:generation]
      assert_equal 1, @stream_session.publisher_generation
      assert_nil @stream_session.actual_publisher_user
      assert_nil @stream_session.broadcast_started_at
      assert_equal @creator.id, @stream_session.started_by_cast_user_id
      assert_equal "旧準備", @stream_session.title
      assert @booth.reload.standby?
      refute_includes connection.attributes.values, result[:participant_token]
      request = @ivs_client.api_requests.find { |r| r[:operation_name] == :create_participant_token }[:params]
      assert_equal [ "PUBLISH" ], request[:capabilities]
      assert_equal @publisher.id.to_s, request[:attributes]["user_id"]
      assert_equal @stream_session.id.to_s, request[:attributes]["stream_session_id"]
      assert_equal "publisher", request[:attributes]["role"]
      refute request.key?(:duration)
    end
  end

  test "S02 同じ要求の再送は保存済み状態を返し重複発行しない" do
    with_publisher_client do
      first = issue_token
      error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(request_id: first[:request_id]) }
      assert_equal "token_already_issued", error.code
      assert_equal "issued", error.details[:state]
      assert_equal first[:request_id], error.details[:request_id]
      refute error.details.key?(:participant_token)
      assert_equal 1, issued_count
      state = StreamSessions::PublisherStateService.new(stream_session: @stream_session,
        actor: @publisher, request_id: first[:request_id]).call
      assert_equal error.details, state
    end
  end

  test "S02 別人の要求IDを流用しても状態を開示せず勝者を取り消さない" do
    with_publisher_client do
      first = issue_token
      error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(actor: @other_publisher, request_id: first[:request_id]) }
      assert_equal "stale_publisher_request", error.code
      assert_empty error.details
      error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(actor: @other_publisher, generation: 1) }
      assert_equal "publisher_in_use", error.code
      assert_equal 1, issued_count
      assert_empty disconnect_requests
      assert_equal @publisher.id, @stream_session.reload.current_publisher_connection.user_id
    end
  end

  test "P05 世代や要求IDがない古い画面と不正な値では発行しない" do
    with_publisher_client do
      [ nil, "", "bad", "1.5", -1, "9223372036854775807" ].each do |generation|
        error = assert_raises(StreamSessions::PublisherControl::Error) { issue_token(generation: generation) }
        assert_equal "stale_publisher_request", error.code
      end
      [ nil, "", "invalid" ].each do |request_id|
        assert_raises(StreamSessions::PublisherControl::Error) { issue_token(request_id: request_id) }
      end
      assert_equal 0, issued_count
      assert_nil @stream_session.reload.current_publisher_connection
    end
  end

  test "P05 閉鎖 終了 現在参照不一致は発行直前に拒否する" do
    with_publisher_client do
      @booth.update!(archived_at: Time.current)
      assert_rejected("not_joinable") { issue_token }
      @booth.update!(archived_at: nil, current_stream_session: nil)
      assert_rejected("not_joinable") { issue_token }
      @booth.update!(current_stream_session: @stream_session)
      @stream_session.update!(status: :ended, ended_at: Time.current)
      assert_rejected("not_joinable") { issue_token }
      assert_equal 0, issued_count
    end
  end

  test "S04 発行前失敗と発行応答消失では実績も開始権も残さない" do
    with_publisher_client do
      @ivs_client.stub_responses(:create_participant_token, [ "AccessDeniedException",
        Seahorse::Client::NetworkingError.new(IOError.new("lost response")) ])
      2.times do
        assert_no_difference "StreamPublisherConnection.count" do
          assert_rejected("publisher_state_unavailable") { issue_token }
        end
        assert_nil @stream_session.reload.current_publisher_connection
        assert_nil @stream_session.actual_publisher_user
        assert_equal 0, @stream_session.publisher_generation
      end
    end
  end

  test "S05 外部発行後のDB保存失敗はトークンを返さず準備を保持する" do
    callback = ->(record) { raise ActiveRecord::RecordInvalid, record }
    StreamPublisherConnection.set_callback(:update, :after, callback)
    with_publisher_client do
      assert_no_difference "StreamPublisherConnection.count" do
        assert_raises(ActiveRecord::RecordInvalid) { issue_token }
      end
      assert_equal 1, issued_count
      assert_nil @stream_session.reload.current_publisher_connection
      assert_equal 0, @stream_session.publisher_generation
      assert_equal @creator.id, @stream_session.started_by_cast_user_id
      assert_nil @stream_session.actual_publisher_user
    end
  ensure
    StreamPublisherConnection.skip_callback(:update, :after, callback)
  end

  test "S04 取消では保存したIDだけを切断し同じ準備で即再試行できる" do
    with_publisher_client do
      first = issue_token
      result = cancel_token(first, actor: @creator)
      assert_equal "cancelled", result[:state]
      assert_equal false, result[:disconnect_pending]
      assert_equal [ { stage_arn: @booth.ivs_stage_arn, participant_id: first[:participant_id] } ], disconnect_requests
      assert_equal 2, @stream_session.reload.publisher_generation
      assert_nil @stream_session.current_publisher_connection
      assert_equal @creator.id, @stream_session.started_by_cast_user_id
      assert_nil @stream_session.actual_publisher_user
      second = issue_token(generation: 2)
      assert_equal 3, second[:generation]
      refute_equal first[:request_id], second[:request_id]
      assert_equal 2, issued_count
      assert_equal 2, @stream_session.stream_publisher_connections.count
    end
  end

  test "S04 取消失敗は開始権を保持し同じ要求の再確認だけを切断する" do
    with_publisher_client do
      first = issue_token
      @ivs_client.stub_responses(:disconnect_participant, [ "AccessDeniedException", {} ])
      result = cancel_token(first)
      assert_equal "cancel_pending", result[:state]
      assert result[:disconnect_pending]
      connection = @stream_session.reload.current_publisher_connection
      assert_nil connection.released_at
      assert_nil connection.disconnected_at
      assert_equal 1, connection.disconnect_attempts
      assert_equal "Aws::IVSRealTime::Errors::AccessDeniedException", connection.last_disconnect_error
      assert connection.next_disconnect_retry_at > Time.current
      assert_rejected("publisher_in_use") { issue_token(generation: 2) }
      assert_equal "cancelled", cancel_token(first)[:state]
      assert_equal 2, connection.reload.disconnect_attempts
      assert connection.released_at
      assert_nil connection.last_disconnect_error
      assert_nil connection.next_disconnect_retry_at
      assert_equal [ first[:participant_id], first[:participant_id] ], disconnect_requests.map { |r| r[:participant_id] }
    end
  end

  test "R03 取消の再送と古い要求の取消で新しい接続を変更しない" do
    with_publisher_client do
      first = issue_token
      assert_equal "cancelled", cancel_token(first)[:state]
      assert_equal "cancelled", cancel_token(first)[:state]
      assert_equal 1, disconnect_requests.size
      second = issue_token(generation: 2)
      assert_rejected("stale_publisher_request") { cancel_token(first) }
      assert_equal second[:request_id], @stream_session.reload.current_publisher_connection.request_id
      assert_equal 1, disconnect_requests.size
    end
  end

  test "取消より成功確定が先なら人物も初回時刻も接続も保持する" do
    with_publisher_client do
      first = issue_token
      @stream_session.reload.current_publisher_connection.update!(confirmed_at: Time.current)
      @stream_session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
        actual_publisher_recorded_at: Time.current, broadcast_started_at: Time.current)
      @booth.update!(status: :live)
      before = @stream_session.attributes
      assert_equal "confirmed", cancel_token(first, actor: @creator)[:state]
      assert_equal before, @stream_session.reload.attributes
      assert_empty disconnect_requests
    end
  end

  test "権限外の取消や他人の状態照会で開始権を操作しない" do
    outsider = User.create!(email: "claim-outsider@example.com", password: "password", role: :cast)
    with_publisher_client do
      first = issue_token
      assert_rejected("forbidden") { cancel_token(first, actor: outsider) }
      assert_rejected("stale_publisher_request") do
        StreamSessions::PublisherStateService.new(stream_session: @stream_session,
          actor: @other_publisher, request_id: first[:request_id]).call
      end
      assert_empty disconnect_requests
    end
  end

  test "S06 外部状態を確認できなければ発行せず別Stageへ波及させない" do
    with_publisher_client do
      @ivs_client.stub_responses(:get_stage, "ResourceNotFoundException")
      assert_rejected("publisher_state_unavailable") { issue_token }
      assert_equal 0, issued_count
      assert_empty StreamPublisherConnection.where(stream_session: @stream_session)
      @ivs_client.stub_responses(:get_stage, ->(context) { { stage: { arn: context.params[:arn] } } })
      other_booth = build_prepared_booth("healthy-stage")
      assert_equal "issued", issue_token(stream_session: other_booth.current_stream_session)[:state]
      assert_nil @stream_session.reload.current_publisher_connection
    end
  end

  private

  def assert_rejected(code)
    error = assert_raises(StreamSessions::PublisherControl::Error) { yield }
    assert_equal code, error.code
  end
end
