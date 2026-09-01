# frozen_string_literal: true

require "test_helper"
require "uri"

class Cast::BoothInfoSharingTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "ブース共有店舗", published: true)
    @cast = User.create!(
      email: "booth-info-sharing-cast@example.com",
      password: "password",
      role: :cast,
      display_name: "ブース共有キャスト"
    )
    @booth = Booth.create!(store: @store, name: "ブース共有対象", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)

    sign_in @cast, scope: :user
  end

  test "booth info opens the destination modal with the booth URL and primary cast message" do
    get cast_booth_path(@booth)

    assert_response :success
    document = Nokogiri::HTML(response.body)
    trigger = document.at_css("button[data-bs-target='#booth-share-modal']")
    assert_equal "modal", trigger["data-bs-toggle"]
    assert_equal "dialog", trigger["aria-haspopup"]
    assert_equal "booth-share-modal", trigger["aria-controls"]
    assert_equal "ブースを共有", trigger.text.strip
    refute trigger["data-controller"]

    assert_share_modal(
      document,
      modal_id: "booth-share-modal",
      expected_text: "ブース共有キャストのブースはこちら🦋",
      expected_url: share_booth_url(@booth)
    )
  end

  test "booth info sharing never adds a stream query for any booth status" do
    stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast
    )

    %i[offline standby live away].each do |status|
      @booth.update!(
        status: status,
        current_stream_session: (stream_session unless status == :offline)
      )

      get cast_booth_path(@booth)

      assert_response :success
      action = share_action("web-share")
      assert_equal share_booth_url(@booth), action["data-share-url"]
      refute_includes action["data-share-url"], "stream="
    end
  end

  test "blank or deleted primary cast display name uses the fixed message" do
    @cast.update!(display_name: " ")
    get cast_booth_path(@booth)
    assert_response :success
    assert_share_text "Butterflyveのブースはこちら🦋"

    @cast.update!(display_name: "削除済みキャスト", deleted_at: Time.current)
    store_admin = User.create!(
      email: "deleted-cast-sharing-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)
    sign_in store_admin, scope: :user

    get cast_booth_path(@booth)
    assert_response :success
    assert_share_text "Butterflyveのブースはこちら🦋"
    refute_includes response.body, @cast.email
  end

  test "booth without a primary cast uses the fixed message" do
    store_admin = User.create!(
      email: "booth-info-sharing-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)
    booth_without_cast = Booth.create!(store: @store, name: "キャスト未設定ブース")
    sign_in store_admin, scope: :user

    get cast_booth_path(booth_without_cast)

    assert_response :success
    assert_share_text "Butterflyveのブースはこちら🦋"
    action = share_action("web-share")
    assert_equal share_booth_url(booth_without_cast), action["data-share-url"]
  end

  private

  def assert_share_text(expected)
    assert_equal expected, share_action("web-share")["data-share-text"]
  end

  def assert_share_modal(document, modal_id:, expected_text:, expected_url:)
    modal = document.at_css("##{modal_id}")
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
    assert_equal "共有URLをコピーしました", copy["data-clipboard-success-message"]
    assert_equal "共有URLのコピーに失敗しました", copy["data-clipboard-failure-message"]
    assert_equal "リンクをコピー", copy.text.strip
    assert copy.at_css(".bi-clipboard")

    assert_external_share_action(
      modal.at_css("[data-share-provider='x']"),
      host: "x.com",
      path: "/intent/tweet",
      icon: ".bi-twitter-x",
      label: "Xで共有",
      expected_text: expected_text,
      expected_url: expected_url,
      expected_hashtags: "Butterflyve,バタフライブ"
    )
    assert_external_share_action(
      modal.at_css("[data-share-provider='line']"),
      host: "social-plugins.line.me",
      path: "/lineit/share",
      icon: ".bi-line",
      label: "LINEで共有",
      expected_text: expected_text,
      expected_url: expected_url,
      expected_hashtags: nil
    )
    refute_includes modal.text, "Instagram"
  end

  def assert_external_share_action(action, host:, path:, icon:, label:, expected_text:, expected_url:,
                                   expected_hashtags:)
    uri = URI.parse(action["href"])
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "https", uri.scheme
    assert_equal host, uri.host
    assert_equal path, uri.path
    assert_equal expected_text, params["text"]
    assert_equal expected_url, params["url"]
    expected_hashtags ? assert_equal(expected_hashtags, params["hashtags"]) : refute(params.key?("hashtags"))
    assert_equal "_blank", action["target"]
    assert_equal "noopener noreferrer", action["rel"]
    assert_equal label, action.text.strip
    assert action.at_css(icon)
  end

  def share_action(provider)
    Nokogiri::HTML(response.body).at_css("[data-share-provider='#{provider}']")
  end
end
