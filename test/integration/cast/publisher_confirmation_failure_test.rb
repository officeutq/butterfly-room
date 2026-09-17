require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::PublisherConfirmationFailureTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    sign_in @publisher, scope: :user
  end

  teardown { ErrorLog.where(stream_session_id: @stream_session.id).delete_all }

  test "本人の未確定要求の最終失敗だけを一度記録し任意のエラー本文は保存しない" do
    with_publisher_client do
      issued = issue_token
      2.times do
        post publisher_confirmation_failure_cast_stream_session_path(@stream_session),
          params: issued.slice(:request_id, :generation).merge(message: "secret-token"), as: :json
        assert_response :no_content
      end
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      assert connection.confirmation_failure_reported_at
      assert_nil connection.confirmed_at
      assert_nil connection.disconnect_requested_at
      log = ErrorLog.where(request_id: issued[:request_id]).sole
      assert_equal "StreamSessions::ReportPublisherConfirmationFailureService::RetryExhausted", log.exception_class
      assert_equal @publisher.id, log.actor_user_id
      assert_equal "error", log.severity
      refute_includes log.attributes.to_json, "secret-token"
    end
  end

  test "他人 古い世代 成功済み 取消済みの要求を失敗として記録しない" do
    with_publisher_client do
      issued = issue_token
      sign_in @other_publisher, scope: :user
      post publisher_confirmation_failure_cast_stream_session_path(@stream_session), params: issued.slice(:request_id, :generation), as: :json
      assert_response :conflict
      sign_in @publisher, scope: :user
      post publisher_confirmation_failure_cast_stream_session_path(@stream_session), params: issued.slice(:request_id).merge(generation: 0), as: :json
      assert_response :conflict
      stub_published_participant(issued)
      confirm_token(issued)
      post publisher_confirmation_failure_cast_stream_session_path(@stream_session), params: issued.slice(:request_id, :generation), as: :json
      assert_response :conflict
      reconnect = issue_token(generation: 1)
      cancel_token(reconnect)
      post publisher_confirmation_failure_cast_stream_session_path(@stream_session), params: reconnect.slice(:request_id, :generation), as: :json
      assert_response :conflict
      assert_empty ErrorLog.where(stream_session_id: @stream_session.id)
    end
  end
end
