require "test_helper"
require "uri"

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
    action = stream_share_action("web-share")
    assert_equal "配信開始管理者の配信はここから！遊びに来てね🦋", action["data-share-text"]
    refute_includes action["data-share-text"], @cast.display_name
    assert_equal share_booth_url(@booth, stream: stream_session.id), action["data-share-url"]
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
    document = Nokogiri::HTML(response.body)
    trigger = document.at_css("button.live-share-button")
    modal = document.at_css("#stream-share-modal")

    assert_equal "配信を共有", trigger["aria-label"]
    assert_equal "配信を共有", trigger["title"]
    assert_equal "modal", trigger["data-bs-toggle"]
    assert_equal "#stream-share-modal", trigger["data-bs-target"]
    assert_equal "dialog", trigger["aria-haspopup"]
    assert_equal "stream-share-modal", trigger["aria-controls"]
    refute trigger["data-controller"]
    assert_includes response.body, "live-overlay-ops-slot"
    assert_equal "配信を共有", trigger.at_css(".visually-hidden").text.strip
    assert modal.ancestors.none? { |ancestor| ancestor["class"]&.split&.include?("cast-live-screen") }
    assert modal.ancestors.none? { |ancestor| ancestor["class"]&.split&.include?("live-overlay-ops-slot") }
    assert_stream_share_modal(
      modal,
      expected_text: "Test Castの配信はここから！遊びに来てね🦋",
      expected_url: share_booth_url(@booth, stream: stream_session.id)
    )
    assert_stream_share_url stream_session
  end

  def assert_stream_share_url(stream_session)
    action = stream_share_action("web-share")
    assert_equal share_booth_url(@booth, stream: stream_session.id), action["data-share-url"]
    refute_match(/(?:timestamp|cache|_)=/, action["data-share-url"])
  end

  def assert_stream_share_text(expected)
    assert_equal expected, stream_share_action("web-share")["data-share-text"]
  end

  def assert_stream_share_modal(modal, expected_text:, expected_url:)
    assert modal
    assert modal.at_css(".modal-dialog-centered")
    assert_equal "共有先を選択", modal.at_css(".modal-title").text.strip
    assert_equal %w[x line web-share copy], modal.css("[data-share-provider]").map { |action| action["data-share-provider"] }

    web_share = modal.at_css("[data-share-provider='web-share']")
    assert_equal "share", web_share["data-controller"]
    assert_equal "click->share#share", web_share["data-action"]
    assert_equal "Butterflyve", web_share["data-share-title"]
    assert_equal expected_text, web_share["data-share-text"]
    assert_equal expected_url, web_share["data-share-url"]
    assert_equal "その他のアプリで共有", web_share.text.strip
    assert web_share.at_css(".bi-share")

    copy = modal.at_css("[data-share-provider='copy']")
    assert_equal "clipboard", copy["data-controller"]
    assert_equal "click->clipboard#copy", copy["data-action"]
    assert_equal expected_url, copy["data-clipboard-text"]
    assert_equal "リンクをコピー", copy.text.strip
    assert copy.at_css(".bi-clipboard")

    assert_external_stream_share_action(
      modal.at_css("[data-share-provider='x']"),
      host: "x.com",
      path: "/intent/tweet",
      icon: ".bi-twitter-x",
      label: "Xで共有",
      expected_text: "#{expected_text}\n\n#Butterflyve #バタフライブ",
      expected_url: expected_url
    )
    assert_external_stream_share_action(
      modal.at_css("[data-share-provider='line']"),
      host: "social-plugins.line.me",
      path: "/lineit/share",
      icon: ".bi-line",
      label: "LINEで共有",
      expected_text: expected_text,
      expected_url: expected_url
    )
    refute_includes modal.text, "Instagram"
  end

  def assert_external_stream_share_action(action, host:, path:, icon:, label:, expected_text:, expected_url:)
    uri = URI.parse(action["href"])
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "https", uri.scheme
    assert_equal host, uri.host
    assert_equal path, uri.path
    assert_equal expected_text, params["text"]
    assert_equal expected_url, params["url"]
    refute params.key?("hashtags")
    assert_equal "_blank", action["target"]
    assert_equal "noopener noreferrer", action["rel"]
    assert_equal label, action.text.strip
    assert action.at_css(icon)
  end

  def stream_share_action(provider)
    Nokogiri::HTML(response.body).at_css("#stream-share-modal [data-share-provider='#{provider}']")
  end
end
