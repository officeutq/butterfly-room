require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::PublisherConfirmationTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    sign_in @publisher, scope: :user
  end

  test "S03 人物IDの改ざんを無視し認証済み本人を原子的に保存して応答消失後も同じ結果を返す" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      params = { request_id: issued[:request_id], generation: issued[:generation], user_id: @creator.id,
        actual_publisher_user_id: @creator.id, broadcast_started_at: 1.year.ago }
      patch start_broadcast_cast_stream_session_path(@stream_session), params: params, as: :json
      assert_response :success
      confirmed = response.parsed_body
      assert_equal @publisher.id, confirmed["actual_publisher_user_id"]
      assert_equal "live", confirmed["booth_status"]
      assert_equal "confirmed", confirmed["state"]
      get publisher_state_cast_stream_session_path(@stream_session), params: { request_id: issued[:request_id] }, as: :json
      assert_response :success
      assert_equal confirmed, response.parsed_body
      patch start_broadcast_cast_stream_session_path(@stream_session), params: params, as: :json
      assert_response :success
      assert_equal confirmed, response.parsed_body
      assert_equal @creator.id, @stream_session.reload.started_by_cast_user_id
    end
  end

  test "P05 旧開始PATCHとstandbyからliveへの別PATCHは配信中を先に作れない" do
    with_publisher_client do
      issued = issue_token
      patch start_broadcast_cast_stream_session_path(@stream_session), as: :json
      assert_response :conflict
      assert_equal "stale_publisher_request", response.parsed_body["error"]
      patch status_cast_booth_path(@booth), params: { to: "live" }, as: :json
      assert_response :conflict
      assert_equal "stale_publisher_request", response.parsed_body["error"]
      patch status_cast_booth_path(@booth), params: { to: "live", stream_session_id: @stream_session.id,
        request_id: issued[:request_id], generation: issued[:generation] }, as: :json
      assert_response :forbidden
      assert_nil @stream_session.reload.actual_publisher_user_id
      assert_nil @stream_session.broadcast_started_at
      assert @booth.reload.standby?
    end
  end

  test "R03 成功後の状態変更は本人の現在要求だけを許し他人と古い世代を拒否する" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      confirm_token(issued)
      params = { to: "away", stream_session_id: @stream_session.id, request_id: issued[:request_id], generation: issued[:generation] }
      patch status_cast_booth_path(@booth), params: params, as: :json
      assert_response :success
      assert @booth.reload.away?
      sign_in @other_publisher, scope: :user
      patch status_cast_booth_path(@booth), params: params.merge(to: "live"), as: :json
      assert_response :forbidden
      patch start_broadcast_cast_stream_session_path(@stream_session), params: params, as: :json
      assert_response :conflict
      sign_in @publisher, scope: :user
      patch status_cast_booth_path(@booth), params: params.merge(to: "live", generation: 0), as: :json
      assert_response :conflict
      assert @booth.reload.away?
      assert_equal @publisher.id, @stream_session.reload.actual_publisher_user_id
    end
  end
end
