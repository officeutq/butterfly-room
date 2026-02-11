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

  test "offline: summary is 200" do
    get cast_booth_path(@booth)
    assert_response :success
  end

  test "offline: live redirects to summary" do
    get live_cast_booth_path(@booth)
    assert_response :redirect
    assert_redirected_to cast_booth_path(@booth)
  end

  test "standby: summary redirects to live" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    get cast_booth_path(@booth)
    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
  end

  test "standby: live is 200" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    get live_cast_booth_path(@booth)
    assert_response :success
  end

  test "standby: finish ends session and redirects to summary" do
    session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    assert @booth.reload.standby?

    post finish_cast_stream_session_path(session)
    assert_response :redirect
    assert_redirected_to cast_booth_path(@booth)

    @booth.reload
    assert @booth.offline?
    assert_nil @booth.current_stream_session_id
  end

  test "live: summary redirects to live" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :live)

    get cast_booth_path(@booth)
    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
  end

  test "away: summary redirects to live" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :away)

    get cast_booth_path(@booth)
    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
  end
end
