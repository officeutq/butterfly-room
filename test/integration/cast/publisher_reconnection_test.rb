require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::PublisherReconnectionTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    sign_in @publisher, scope: :user
  end

  test "R02 再読込は本人の実績と現在世代で復帰し新要求の確定後も初回時刻を維持する" do
    with_publisher_client do
      first = issue_token
      stub_published_participant(first)
      confirmed = confirm_token(first)
      @booth.update!(status: :away)
      get live_cast_booth_path(@booth)
      assert_response :success
      assert_select '[data-ivs-publisher-auto-resume-on-entry-value="true"]'
      assert_select '[data-ivs-publisher-publisher-generation-value="1"]'
      assert_select "[data-ivs-publisher-existing-request-id-value='#{first[:request_id]}']"
      assert_select '[data-ivs-publisher-existing-request-state-value="confirmed"]'
      post stream_session_ivs_participant_tokens_path(@stream_session), params: {
        role: "publisher", request_id: SecureRandom.uuid, expected_generation: 1 }, as: :json
      assert_response :success
      second = response.parsed_body.symbolize_keys
      assert_equal 2, second[:generation]
      assert_equal "away", second[:booth_status]
      assert_equal @publisher.id, second[:actual_publisher_user_id]
      stub_published_participant(second)
      patch start_broadcast_cast_stream_session_path(@stream_session), params: {
        request_id: second[:request_id], generation: second[:generation] }, as: :json
      assert_response :success
      assert_equal "confirmed", response.parsed_body["state"]
      assert_equal confirmed[:broadcast_started_at], @stream_session.reload.broadcast_started_at
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
      assert_equal @creator.id, @stream_session.started_by_cast_user_id
      assert @booth.reload.live?
      assert_equal [ first[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  end

  test "R02 未確定要求の復帰情報は発行した本人の画面だけに含める" do
    with_publisher_client do
      first = issue_token
      get live_cast_booth_path(@booth)
      assert_response :success
      assert_select "[data-ivs-publisher-existing-request-id-value='#{first[:request_id]}']"
      assert_select '[data-ivs-publisher-existing-request-state-value="issued"]'
      sign_in @other_publisher, scope: :user
      get live_cast_booth_path(@booth)
      assert_response :success
      assert_select "[data-ivs-publisher-existing-request-id-value]", count: 0
      assert_select '[data-ivs-publisher-auto-resume-on-entry-value="false"]'
      assert_empty disconnect_requests
    end
  end

  test "R02 Xと別人の再訪ではYの実績を引き継がせない" do
    with_publisher_client do
      first = issue_token
      stub_published_participant(first)
      confirm_token(first)
      [ @creator, @other_publisher ].each do |actor|
        sign_in actor, scope: :user
        get live_cast_booth_path(@booth)
        assert_redirected_to cast_booth_path(@booth)
        follow_redirect!
        assert_includes response.body, "このブースはすでに他の人が配信中です"
        post stream_session_ivs_participant_tokens_path(@stream_session), params: {
          role: "publisher", request_id: SecureRandom.uuid, expected_generation: 1 }, as: :json
        assert_response :conflict
        assert_equal "publisher_in_use", response.parsed_body["error"]
      end
      assert_equal 1, issued_count
      assert_empty disconnect_requests
      assert_equal @publisher.id, @stream_session.reload.actual_publisher_user_id
    end
  end
end
