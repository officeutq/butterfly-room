require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::PublisherEndingTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    sign_in @publisher, scope: :user
  end

  test "E01 旧準備を世代0で終了し応答が失われても同じリザルトを返す" do
    with_publisher_client do
      2.times do
        post finish_cast_stream_session_path(@stream_session), params: { generation: 0 }, as: :json
        assert_response :ok
        assert_equal "ended", response.parsed_body["state"]
        assert_equal cast_stream_session_path(@stream_session), response.parsed_body["redirect_url"]
      end
      assert @stream_session.reload.ended?
      assert_nil @stream_session.actual_publisher_user_id
    end
  end

  test "E02 他の管理者の通常終了は拒否し明示した管理終了を許可する" do
    with_publisher_client do
      issued = begin_broadcast
      sign_in @other_publisher, scope: :user
      post finish_cast_stream_session_path(@stream_session), params: issued.slice(:request_id, :generation), as: :json
      assert_response :forbidden
      refute @stream_session.reload.ended?
      post force_end_admin_booth_path(@booth), params: { stream_session_id: @stream_session.id, generation: 1 }, as: :json
      assert_response :ok
      assert @stream_session.reload.ended?
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
    end
  end

  test "E05 切断失敗は202と返却完了を案内しリザルトから再確認できる" do
    with_publisher_client do
      issued = begin_broadcast
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      post finish_cast_stream_session_path(@stream_session), params: issued.slice(:request_id, :generation), as: :json
      assert_response :accepted
      assert_equal true, response.parsed_body["disconnect_pending"]
      get cast_stream_session_path(@stream_session)
      assert_response :ok
      assert_select "form[action='#{retry_publisher_disconnect_cast_booth_path(@booth)}']"
      @ivs_client.stub_responses(:disconnect_participant, {})
      connection = @stream_session.reload.current_publisher_connection
      travel_to(connection.next_disconnect_retry_at + 1.second) do
        post retry_publisher_disconnect_cast_booth_path(@booth), as: :json
      end
      assert_response :ok
      assert_equal false, response.parsed_body["disconnect_pending"]
    end
  end

  test "E03 世代が変わった管理画面の閉鎖要求は開始中の準備を変更しない" do
    with_publisher_client do
      issue_token
      patch archive_admin_booth_path(@booth), params: { stream_session_id: @stream_session.id, generation: 0 }, as: :json
      assert_response :conflict
      assert_equal "stale_publisher_request", response.parsed_body["error"]
      refute @booth.reload.archived?
      assert_empty disconnect_requests
    end
  end

  test "R03 対象を指定しない旧管理終了と旧通常終了を拒否する" do
    with_publisher_client do
      begin_broadcast
      post force_end_admin_booth_path(@booth), as: :json
      assert_response :conflict
      post finish_cast_stream_session_path(@stream_session), as: :json
      assert_response :conflict
      assert_empty disconnect_requests
    end
  end

  test "E05 閉鎖後も管理画面に切断待ちと再確認を表示する" do
    with_publisher_client do
      issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      patch archive_admin_booth_path(@booth), params: { stream_session_id: @stream_session.id, generation: 1 }
      assert_response :see_other
      assert @booth.reload.archived?
      get admin_booths_path(archived: 1)
      assert_response :ok
      assert_select "form[action='#{retry_publisher_disconnect_admin_booth_path(@booth)}']"
      @ivs_client.stub_responses(:disconnect_participant, {})
      connection = @stream_session.reload.current_publisher_connection
      travel_to(connection.next_disconnect_retry_at + 1.second) do
        post retry_publisher_disconnect_admin_booth_path(@booth), as: :json
      end
      assert_response :ok
      assert_equal false, response.parsed_body["disconnect_pending"]
    end
  end

  test "E05 切断待ちの準備画面は開始させず同じブースの再確認を表示する" do
    with_publisher_client do
      issued = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(issued)
      get live_cast_booth_path(@booth)
      assert_response :accepted
      assert_select "form[action='#{retry_publisher_disconnect_cast_booth_path(@booth)}']"
      refute @stream_session.reload.ended?
    end
  end

  test "再確認は他店から拒否し切断意図のない他人の接続を切断しない" do
    with_publisher_client do
      begin_broadcast
      post retry_publisher_disconnect_admin_booth_path(@booth), as: :json
      assert_response :ok
      assert_empty disconnect_requests
      outsider = User.create!(email: "ending-outsider@example.com", password: "password", role: :cast)
      sign_in outsider, scope: :user
      post retry_publisher_disconnect_cast_booth_path(@booth), as: :json
      assert_response :forbidden
      assert_empty disconnect_requests
    end
  end

  private

  def begin_broadcast
    issued = issue_token
    stub_published_participant(issued)
    confirm_token(issued)
    issued
  end
end
