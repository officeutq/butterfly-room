require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::PublisherConnectionsTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    sign_in @publisher, scope: :user
  end

  test "発行 状態取得 取消 再発行を同じ旧準備で行う" do
    with_publisher_client do
      request_id = SecureRandom.uuid
      post stream_session_ivs_participant_tokens_path(@stream_session),
        params: { role: "publisher", request_id: request_id, expected_generation: 0, user_id: @creator.id }, as: :json
      assert_response :success
      issued = response.parsed_body
      assert_equal "issued", issued["state"]
      assert_equal @publisher.id, @stream_session.reload.current_publisher_connection.user_id
      assert_equal @creator.id, @stream_session.started_by_cast_user_id
      assert_nil @stream_session.actual_publisher_user

      get publisher_state_cast_stream_session_path(@stream_session), params: { request_id: request_id }, as: :json
      assert_response :success
      assert_equal "issued", response.parsed_body["state"]
      refute response.parsed_body.key?("participant_token")

      post cancel_broadcast_cast_stream_session_path(@stream_session), params: { request_id: request_id, generation: 1 }, as: :json
      assert_response :success
      assert_equal "cancelled", response.parsed_body["state"]
      assert_equal 2, response.parsed_body["current_generation"]
      assert_nil @stream_session.reload.actual_publisher_user

      post stream_session_ivs_participant_tokens_path(@stream_session),
        params: { role: "publisher", request_id: SecureRandom.uuid, expected_generation: 2 }, as: :json
      assert_response :success
      assert_equal 3, response.parsed_body["generation"]
      refute_equal issued["participant_id"], response.parsed_body["participant_id"]
    end
  end

  test "取消の切断失敗は202と確認待ち状態を返す" do
    with_publisher_client do
      first = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      post cancel_broadcast_cast_stream_session_path(@stream_session),
        params: { request_id: first[:request_id], generation: first[:generation] }, as: :json
      assert_response :accepted
      assert_equal "cancel_pending", response.parsed_body["state"]
      assert_equal "publisher_disconnect_pending", response.parsed_body["error"]
      assert_equal true, response.parsed_body["disconnect_pending"]
      assert_nil @stream_session.reload.current_publisher_connection.released_at
    end
  end

  test "同一要求の再送は409で状態を返し識別情報のない旧画面は再読込を案内する" do
    with_publisher_client do
      first = issue_token
      post stream_session_ivs_participant_tokens_path(@stream_session),
        params: { role: "publisher", request_id: first[:request_id], expected_generation: 0 }, as: :json
      assert_response :conflict
      assert_equal "token_already_issued", response.parsed_body["error"]
      assert_equal "issued", response.parsed_body["state"]
      refute response.parsed_body.key?("participant_token")
      post stream_session_ivs_participant_tokens_path(@stream_session), params: { role: "publisher" }, as: :json
      assert_response :conflict
      assert_equal "stale_publisher_request", response.parsed_body["error"]
      assert_equal 1, issued_count
      assert_empty disconnect_requests
    end
  end

  test "viewer契約は有効化後も変えずstandbyでは参加させない" do
    with_publisher_client do
      post stream_session_ivs_participant_tokens_path(@stream_session), params: { role: "viewer" }, as: :json
      assert_response :conflict
      assert_equal "not_joinable", response.parsed_body["error"]
      @booth.update!(status: :live)
      post stream_session_ivs_participant_tokens_path(@stream_session), params: { role: "viewer" }, as: :json
      assert_response :success
      assert_equal "viewer", response.parsed_body["role"]
      refute response.parsed_body.key?("request_id")
      assert_empty StreamPublisherConnection.where(stream_session: @stream_session)
      request = @ivs_client.api_requests.find { |r| r[:operation_name] == :create_participant_token }[:params]
      assert_equal [ "SUBSCRIBE" ], request[:capabilities]
    end
  end

  test "有効化前のpublisher応答を維持し新しい取消APIは無効にする" do
    with_publisher_client(enabled: "false") do
      post stream_session_ivs_participant_tokens_path(@stream_session), params: { role: "publisher" }, as: :json
      assert_response :success
      refute response.parsed_body.key?("request_id")
      assert_empty StreamPublisherConnection.where(stream_session: @stream_session)
      post cancel_broadcast_cast_stream_session_path(@stream_session), params: { request_id: SecureRandom.uuid, generation: 0 }, as: :json
      assert_response :not_found
      assert_empty disconnect_requests
    end
  end
end
