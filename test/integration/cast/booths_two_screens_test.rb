require "test_helper"

class Cast::BoothsTwoScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @store = Store.create!(name: "Test Store", published: true)
    @cast = User.create!(
      email: "cast@example.com",
      password: "password",
      role: :cast,
      display_name: "Test Cast"
    )
    @customer = User.create!(email: "customer@example.com", password: "password", role: :customer)

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
    assert_cast_booth_share_button_rendered
  end

  test "live: live screen renders booth share button in ops slot" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :live)

    get live_cast_booth_path(@booth)
    assert_response :success
    assert_cast_booth_share_button_rendered
  end

  test "away: live screen renders the same stream sharing URL" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :away)

    get live_cast_booth_path(@booth)

    assert_response :success
    assert_cast_booth_share_button_rendered
  end

  test "sharing URL keeps the current stream ID across standby live and away" do
    stream_session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call

    %i[standby live away live].each do |status|
      @booth.update!(status: status)

      get live_cast_booth_path(@booth)

      assert_response :success
      assert_equal stream_session.id, @booth.reload.current_stream_session_id
      assert_stream_share_url stream_session
    end
  end

  test "live sharing text uses the actual stream starter instead of the primary cast" do
    store_admin = User.create!(
      email: "stream-sharing-admin@example.com",
      password: "password",
      role: :store_admin,
      display_name: "配信開始管理者"
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)
    stream_session = StreamSessions::StartService.new(booth: @booth, actor: store_admin).call

    get live_cast_booth_path(@booth)

    assert_response :success
    button = Nokogiri::HTML(response.body).at_css("button.live-share-button")
    assert_equal "配信開始管理者の配信はここから！遊びに来てね🦋", button["data-share-text"]
    refute_includes button["data-share-text"], @cast.display_name
    assert_equal share_booth_url(@booth, stream: stream_session.id), button["data-share-url"]
  end

  test "live sharing text falls back for blank or deleted stream starter" do
    stream_session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @cast.update!(display_name: " ")

    get live_cast_booth_path(@booth)

    assert_response :success
    assert_stream_share_text "配信はここから！遊びに来てね🦋"

    @cast.update!(display_name: "削除済み配信者", deleted_at: Time.current)
    store_admin = User.create!(
      email: "deleted-starter-sharing-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)
    sign_in store_admin, scope: :user

    get live_cast_booth_path(@booth)

    assert_response :success
    assert_stream_share_text "配信はここから！遊びに来てね🦋"
    refute_includes response.body, @cast.email
    assert_equal stream_session.id, @booth.reload.current_stream_session_id
  end

  test "viewer live screen does not render cast booth share button" do
    StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :live)

    sign_out :user
    sign_in @customer, scope: :user

    get booth_path(@booth)
    assert_response :success
    refute_includes response.body, 'aria-label="ブースを共有"'
    refute_includes response.body, 'data-controller="share"'
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

  private

  def assert_cast_booth_share_button_rendered
    stream_session = @booth.reload.current_stream_session

    assert_includes response.body, 'aria-label="配信を共有"'
    assert_includes response.body, 'title="配信を共有"'
    assert_includes response.body, 'data-controller="share"'
    assert_includes response.body, "share#share"
    assert_includes response.body, 'data-share-title="Butterflyve"'
    assert_includes response.body, 'data-share-text="Test Castの配信はここから！遊びに来てね🦋"'
    assert_includes response.body, "live-overlay-ops-slot"
    assert_includes response.body, "live-ops-btn live-share-button"
    assert_includes response.body, "live-share-button"
    assert_includes response.body, '<span class="visually-hidden">配信を共有</span>'
    assert_stream_share_url stream_session
  end

  def assert_stream_share_url(stream_session)
    button = Nokogiri::HTML(response.body).at_css("button.live-share-button")
    assert_equal share_booth_url(@booth, stream: stream_session.id), button["data-share-url"]
    refute_match(/(?:timestamp|cache|_)=/, button["data-share-url"])
  end

  def assert_stream_share_text(expected)
    button = Nokogiri::HTML(response.body).at_css("button.live-share-button")
    assert_equal expected, button["data-share-text"]
  end
end
