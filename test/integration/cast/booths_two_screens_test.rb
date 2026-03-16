require "test_helper"

class Cast::BoothsTwoScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @store = Store.create!(name: "Test Store")
    @cast  = User.create!(email: "cast@example.com", password: "password", role: :cast)

    @booth = Booth.create!(
      store: @store,
      name: "Test Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/abc"
    )

    BoothCast.create!(booth: @booth, cast_user: @cast)

    sign_in @cast, scope: :user
  end

  test "offline: enter auto starts standby and redirects to live" do
    assert_difference "StreamSession.count", 1 do
      get enter_booth_path(@booth)
    end

    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)

    @booth.reload
    assert @booth.standby?
    assert @booth.current_stream_session_id.present?
  end

  test "offline: live redirects to cast booths index" do
    get live_cast_booth_path(@booth)
    assert_response :redirect
    assert_redirected_to cast_booths_path
  end

  test "standby: enter reuses existing session and redirects to live" do
    session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    assert_no_difference "StreamSession.count" do
      get enter_booth_path(@booth)
    end

    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
    assert_equal session.id, @booth.reload.current_stream_session_id
  end

  test "standby: live is 200" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    get live_cast_booth_path(@booth)
    assert_response :success
  end

  test "standby: finish ends session and redirects to result" do
    session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    post finish_cast_stream_session_path(session)
    assert_response :redirect
    assert_redirected_to cast_stream_session_path(session)

    @booth.reload
    assert @booth.offline?
    assert_nil @booth.current_stream_session_id
  end

  test "live by self: enter redirects to live without creating new session" do
    session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :live)

    assert_no_difference "StreamSession.count" do
      get enter_booth_path(@booth)
    end

    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
    assert_equal session.id, @booth.reload.current_stream_session_id
  end

  test "away by self: enter redirects to live without creating new session" do
    session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :away)

    assert_no_difference "StreamSession.count" do
      get enter_booth_path(@booth)
    end

    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
    assert_equal session.id, @booth.reload.current_stream_session_id
  end

  test "standby: live subscribes comments but does not render comments UI" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    get live_cast_booth_path(@booth)
    assert_response :success

    assert_includes response.body, "turbo-cable-stream-source"
    assert_includes response.body, 'id="comments"'
    refute_includes response.body, 'id="comment_form"'
  end

  test "standby: cannot create comment (turbo_stream) and returns 409" do
    session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    assert_no_difference "Comment.count" do
      post stream_session_comments_path(session),
           params: { comment: { body: "hello" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :conflict
  end
end
