require "test_helper"

class ActualBroadcasterTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Actual Publisher", published: true)
    @x = User.create!(email: "actual-x@example.test", password: "password", role: :system_admin, display_name: "準備者X")
    @y = User.create!(email: "actual-y@example.test", password: "password", role: :system_admin, display_name: "配信者Y")
    @booth = Booth.create!(store: @store, name: "Actual Publisher", status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/actual")
    @session = StreamSessions::StartService.new(booth: @booth, actor: @x).call
    @attempt_id = SecureRandom.uuid
    @sdk = Aws::IVSRealTime::Client.new(stub_responses: true, region: "ap-northeast-1")
    @sdk.stub_responses(:get_stage, ->(_) { { stage: { arn: @booth.ivs_stage_arn, active_session_id: @published ? "ivs-session" : nil } } })
    @sdk.stub_responses(:list_participants, { participants: [ { participant_id: "participant-y" } ] })
    @sdk.stub_responses(:get_participant, ->(_) { { participant: { participant_id: "participant-y", state: "CONNECTED", published: true,
      attributes: { "role" => "publisher", "user_id" => @y.id.to_s, "stream_session_id" => @session.id.to_s, "publish_attempt_id" => @attempt_id } } } })
    @sdk.stub_responses(:create_participant_token, { participant_token: { token: "opaque-token", participant_id: "participant-y", expiration_time: 1.minute.from_now } })
    Ivs::Client.factory = ->(**) { Ivs::Client.new(client: @sdk) }
  end

  teardown { Ivs::Client.reset_factory! }

  test "Y starts Xs preparation and owns display moderation status and history" do
    sign_in @y
    post stream_session_ivs_participant_tokens_path(@session), params: { role: "publisher", publish_attempt_id: @attempt_id }, as: :json
    assert_response :success
    assert_nil @session.reload.broadcast_started_by_user_id
    @published = true
    patch start_broadcast_cast_stream_session_path(@session), params: { publish_attempt_id: @attempt_id, user_id: @x.id }, as: :json
    assert_response :success
    assert @session.reload.broadcaster?(@y)
    assert @booth.reload.live?
    patch status_cast_booth_path(@booth), params: { to: "away", publish_attempt_id: @attempt_id }, as: :json
    assert_response :success
    assert @booth.reload.away?

    comment = @session.comments.create!(booth: @booth, user: @x, body: "準備者のコメント")
    patch hide_stream_session_comment_path(@session, comment), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert comment.reload.hidden?
    sign_in @x
    patch unhide_stream_session_comment_path(@session, comment), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
    get live_cast_booth_path(@booth)
    assert_redirected_to cast_booths_path
    post stream_session_ivs_participant_tokens_path(@session), params: { role: "publisher", publish_attempt_id: SecureRandom.uuid }, as: :json
    assert_response :conflict
    patch start_broadcast_cast_stream_session_path(@session), params: { publish_attempt_id: @attempt_id }, as: :json
    assert_response :conflict

    get booth_path(@booth)
    assert_select ".meta-name", text: "配信者Y"
    assert_select ".meta-name a[href=?]", user_path(@y)
    refute_select = Nokogiri::HTML(response.body).at_css("#comment_#{comment.id}")
    refute_includes refute_select["class"], "comment-from-broadcaster"

    sign_in @y
    post finish_cast_stream_session_path(@session), params: { publish_attempt_id: @attempt_id }, as: :json
    assert_response :success
    assert @session.reload.ended?
    get cast_stream_session_path(@session)
    assert_response :success
    assert_includes response.body, "配信者Y"
    assert_equal @x.id, @session.started_by_cast_user_id
    assert @session.broadcaster?(@y)
    assert_equal({ stage_arn: @session.ivs_stage_arn, participant_id: "participant-y" },
      @sdk.api_requests.find { |r| r[:operation_name] == :disconnect_participant }[:params])
  end

  test "missing attempt and closed booth cannot start through stale requests" do
    sign_in @y
    patch start_broadcast_cast_stream_session_path(@session), as: :json
    assert_response :conflict
    post stream_session_ivs_participant_tokens_path(@session), params: { role: "publisher" }, as: :json
    assert_response :conflict
    @booth.update!(archived_at: Time.current)
    post stream_session_ivs_participant_tokens_path(@session), params: { role: "publisher", publish_attempt_id: @attempt_id }, as: :json
    assert_response :conflict
    assert_nil @session.reload.broadcast_started_at
    assert_empty @sdk.api_requests
  end
end
