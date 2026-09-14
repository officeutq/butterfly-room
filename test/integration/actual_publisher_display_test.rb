require "test_helper"
require_relative "../support/publisher_connection_test_support"

class ActualPublisherDisplayTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport
  include ActionCable::TestHelper

  setup do
    build_publisher_fixture
    @stream_session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: Time.current)
    @booth.update!(status: :live)
    @creator.update!(display_name: "Creator X")
    @publisher.update!(display_name: "Publisher Y")
    @other_publisher.update!(display_name: "Admin Other")
    @assigned = User.create!(email: "display-z-#{SecureRandom.hex(6)}@example.com", password: "password",
      role: :cast, display_name: "Assigned Z")
    BoothCast.where(booth: @booth).delete_all
    BoothCast.create!(booth: @booth, cast_user: @assigned)
  end

  test "H01 視聴の初期表示と更新通知はYを表示しゲストに管理者プロフィールリンクを出さない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      get booth_path(@booth)
      assert_response :ok
      assert_select ".meta-name", text: "Publisher Y"
      assert_select ".meta-name a", count: 0
      assert_select ".meta-avatar [title='Publisher Y']", count: 1
      sign_in @other_publisher, scope: :user
      get booth_path(@booth)
      assert_select ".meta-name a[href='#{user_path(@publisher)}']", text: "Publisher Y"
      guest_channel = Turbo::StreamsChannel.send(:stream_name_from, [ @booth, :stream_state, :guest ])
      messages = capture_broadcasts(guest_channel) { StreamSessionNotifier.broadcast_stream_state(booth: @booth) }
      fragment = Nokogiri::HTML.fragment(messages.sole)
      assert_equal "Publisher Y", fragment.at_css(".meta-name").text.strip
      assert_empty fragment.css(".meta-name a")
    end
  end

  test "H04 キャストの公開プロフィールはゲストにもリンクしシステム管理者は本人用だけに限定する" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      @publisher.update!(role: :cast)
      get booth_path(@booth)
      assert_select ".meta-name a[href='#{user_path(@publisher)}']", count: 1
      @publisher.update!(role: :system_admin)
      get booth_path(@booth)
      assert_select ".meta-name a, .meta-name [data-controller='self-profile-link']", count: 0
      sign_in @other_publisher, scope: :user
      get booth_path(@booth)
      assert_select ".meta-name a", count: 0
      assert_select ".meta-name [data-controller='self-profile-link'][data-self-profile-link-user-id-value='#{@publisher.id}']", count: 1
      get user_path(@publisher)
      assert_response :not_found
    end
  end

  test "H04 不明の配信情報はXやZへ代替せず名前とリンクと画像を一緒に扱う" do
    @stream_session.update!(actual_publisher_user: nil, actual_publisher_source: nil, actual_publisher_recorded_at: nil)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      get booth_path(@booth)
      assert_select ".meta-name", text: "配信者不明"
      assert_select ".meta-name a, .meta-avatar img, .meta-avatar [title]", count: 0
      sign_in @other_publisher, scope: :user
      @stream_session.update!(broadcast_started_at: nil)
      @booth.update!(status: :standby)
      get meta_display_cast_stream_session_path(@stream_session)
      assert_response :ok
      assert_select ".meta-name", text: "配信未開始"
      assert_select ".meta-name a", count: 0
    end
  end

  test "H01 リザルト・履歴・指定した過去共有は次の配信者や担当者へ変わらない" do
    @stream_session.update!(status: :ended, ended_at: Time.current)
    next_session = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @assigned,
      started_at: Time.current, broadcast_started_at: Time.current, status: :live,
      actual_publisher_user: @other_publisher, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: Time.current)
    @booth.update!(current_stream_session: next_session)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @other_publisher, scope: :user
      get cast_stream_session_path(@stream_session)
      assert_response :ok
      assert_select ".card-body", text: /Publisher Y/
      get cast_booth_stream_sessions_path(@booth)
      assert_response :ok
      assert_select "a[href='#{cast_stream_session_path(@stream_session)}']", text: /Publisher Y/
      get share_booth_path(@booth, stream: @stream_session.id)
      assert_response :ok
      assert_select "meta[property='og:description'][content='Publisher Yのライブ配信をButterflyveで楽しもう']", count: 1
      assert_select "meta[property='og:url'][content='#{share_booth_url(@booth, stream: @stream_session.id)}']", count: 1
      get share_booth_path(@booth)
      assert_select "meta[property='og:description'][content='Assigned Zのライブ配信をButterflyveで楽しもう']", count: 1
    end
  end

  test "H04 不明履歴・退会者の表示と非公開店舗の共有制限を維持する" do
    @stream_session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session_id: nil)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @other_publisher, scope: :user
      @publisher.update!(deleted_at: Time.current, display_name: "退会済みユーザー")
      get cast_stream_session_path(@stream_session)
      assert_select ".card-body", text: /退会済みユーザー/
      get share_booth_path(@booth, stream: @stream_session.id)
      assert_select "meta[property='og:description'][content='ライブ配信をButterflyveで楽しもう']", count: 1
      @stream_session.update!(actual_publisher_user: nil, actual_publisher_source: nil, actual_publisher_recorded_at: nil)
      get cast_booth_stream_sessions_path(@booth)
      assert_select "a[href='#{cast_stream_session_path(@stream_session)}']", text: /配信者不明/
      get share_booth_path(@booth, stream: @stream_session.id)
      assert_select "meta[property='og:description'][content^='配信者不明。']", count: 1
      @store.update!(published: false)
      get share_booth_path(@booth, stream: @stream_session.id)
      assert_response :not_found
    end
  end

  test "H01 同じ準備の共有を開始後に再取得すると全共有先の人物がYへ更新される" do
    @stream_session.update!(actual_publisher_user: nil, actual_publisher_source: nil,
      actual_publisher_recorded_at: nil, broadcast_started_at: nil)
    @booth.update!(status: :standby)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @other_publisher, scope: :user
      get share_cast_stream_session_path(@stream_session)
      assert_response :ok
      assert_select "[data-share-provider='web-share'][data-share-text^='配信未開始。']", count: 1
      @stream_session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
        actual_publisher_recorded_at: Time.current, broadcast_started_at: Time.current)
      @booth.update!(status: :live)
      get share_cast_stream_session_path(@stream_session)
      assert_response :ok
      assert_select "[data-share-provider='web-share'][data-share-text='Publisher Yの配信はここから！遊びに来てね🦋']", count: 1
      %w[x line].each do |provider|
        href = Nokogiri::HTML(response.body).at_css("[data-share-provider='#{provider}']")["href"]
        assert_includes URI.decode_www_form(URI(href).query).to_h["text"], "Publisher Y"
        refute_includes URI.decode_www_form(URI(href).query).to_h["text"], "Creator X"
      end
      get meta_display_cast_stream_session_path(@stream_session)
      assert_select ".meta-name", text: "Publisher Y"
      sign_in @creator, scope: :user
      get share_cast_stream_session_path(@stream_session)
      assert_response :forbidden
    end
  end

  test "H01 通報画面の配信者だけYとし投稿者と通報者の記録を保持する" do
    comment = Comment.create!(stream_session: @stream_session, booth: @booth, user: @assigned, body: "Reported comment")
    report = StreamSessions::Comments::ReportService.new(comment: comment, reporter_user: @creator).call
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @other_publisher, scope: :user
      get admin_comment_reports_path
      assert_response :ok
      assert_select "#report_card_comment_#{comment.id}", text: /Publisher Y/
      assert_select "#report_card_comment_#{comment.id}", text: /Assigned Z/
      assert_equal @creator.id, report.reload.reporter_user_id
      assert_equal @assigned.id, comment.reload.user_id
    end
  end

  test "H01 アバター画像とプロフィールリンクも配信者Yを指す" do
    [ @creator, @publisher, @assigned ].each do |user|
      user.avatar.attach(io: File.open(Rails.root.join("test/fixtures/files/sample.png")),
        filename: "publisher-avatar-#{user.id}.png", content_type: "image/png")
    end
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @other_publisher, scope: :user
      get booth_path(@booth)
      assert_select ".meta-avatar img[src$='publisher-avatar-#{@publisher.id}.png']", count: 1
      assert_select ".meta-name a[href='#{user_path(@publisher)}']", count: 1
      assert_select ".meta-avatar img[src$='publisher-avatar-#{@creator.id}.png']", count: 0
      assert_select ".meta-avatar img[src$='publisher-avatar-#{@assigned.id}.png']", count: 0
    end
  end
end
