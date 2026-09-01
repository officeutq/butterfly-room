# frozen_string_literal: true

require "test_helper"
require "mini_magick"

class BoothSharingTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "共有テスト店舗", published: true)
    @cast = User.create!(
      email: "booth-sharing-cast@example.com",
      password: "password",
      role: :cast,
      display_name: "共有キャスト"
    )
    @booth = Booth.create!(store: @store, name: "共有テストブース", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)
    @stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      title: "共有テスト配信",
      started_at: Time.current,
      started_by_cast_user: @cast
    )
  end

  test "guest receives booth sharing OGP and immediate booth redirect markup" do
    get share_booth_path(@booth)

    assert_response :success
    doc = Nokogiri::HTML(response.body)

    assert_equal @booth.name, doc.at_css("meta[property='og:title']")["content"]
    assert_equal "共有キャストのライブ配信をButterflyveで楽しもう",
                 doc.at_css("meta[property='og:description']")["content"]
    assert_equal share_booth_url(@booth), doc.at_css("meta[property='og:url']")["content"]
    assert_equal share_booth_url(@booth), doc.at_css("link[rel='canonical']")["href"]
    assert_equal "website", doc.at_css("meta[property='og:type']")["content"]
    assert_equal "Butterflyve（バタフライブ）", doc.at_css("meta[property='og:site_name']")["content"]
    assert_equal "summary_large_image", doc.at_css("meta[name='twitter:card']")["content"]
    image_url = doc.at_css("meta[property='og:image']")["content"]
    assert_match %r{\Ahttps?://}, image_url
    assert_match %r{/assets/booth-share-ogp(?:-[0-9a-f]+)?\.jpg\z}, image_url
    assert_includes doc.at_css("meta[name='robots']")["content"], "noindex"
    refute_includes doc.at_css("meta[name='robots']")["content"], "nofollow"

    redirect_element = doc.at_css("[data-controller='auto-redirect']")
    assert_equal booth_url(@booth), redirect_element["data-auto-redirect-url-value"]
    assert_equal "0", redirect_element["data-auto-redirect-delay-value"]
    assert_equal booth_url(@booth), doc.at_css("main a")["href"]
  end

  test "valid current or ended stream receives stream-specific OGP" do
    [ :live, :ended ].each do |status|
      @stream_session.update!(status: status, ended_at: (Time.current if status == :ended))

      get share_booth_path(@booth, stream: @stream_session.id)

      assert_response :success
      doc = Nokogiri::HTML(response.body)
      expected_url = share_booth_url(@booth, stream: @stream_session.id)
      assert_equal @stream_session.title, doc.at_css("meta[property='og:title']")["content"]
      assert_equal expected_url, doc.at_css("meta[property='og:url']")["content"]
      assert_equal expected_url, doc.at_css("link[rel='canonical']")["href"]
    end
  end

  test "stream without title falls back to booth name" do
    @stream_session.update!(title: " ")

    get share_booth_path(@booth, stream: @stream_session.id)

    assert_response :success
    assert_equal @booth.name,
                 Nokogiri::HTML(response.body).at_css("meta[property='og:title']")["content"]
  end

  test "invalid missing and other booth streams fall back to booth sharing" do
    other_store = Store.create!(name: "別店舗", published: true)
    other_booth = Booth.create!(store: other_store, name: "別ブース")
    other_stream = StreamSession.create!(
      booth: other_booth,
      store: other_store,
      status: :live,
      title: "非公開にすべき別配信",
      started_at: Time.current,
      started_by_cast_user: @cast
    )

    [ "not-a-number", "1invalid", "999999999999999999999999", other_stream.id ].each do |stream|
      get share_booth_path(@booth, stream: stream)

      assert_response :success
      doc = Nokogiri::HTML(response.body)
      assert_equal @booth.name, doc.at_css("meta[property='og:title']")["content"]
      assert_equal share_booth_url(@booth), doc.at_css("meta[property='og:url']")["content"]
      refute_includes response.body, other_stream.title
    end
  end

  test "unpublished archived and missing booths return not found" do
    @store.update!(published: false)
    get share_booth_path(@booth)
    assert_response :not_found

    @store.update!(published: true)
    @booth.update!(archived_at: Time.current)
    get share_booth_path(@booth)
    assert_response :not_found

    get share_booth_path(id: 0)
    assert_response :not_found
  end

  test "crawler and browser user agents receive the same public OGP" do
    user_agents = [
      "Mozilla/5.0 AppleWebKit/537.36 Chrome/120.0 Safari/537.36",
      "Twitterbot/1.0",
      "facebookexternalhit/1.1",
      "Slackbot-LinkExpanding 1.0"
    ]

    results = user_agents.map do |user_agent|
      get share_booth_path(@booth, stream: @stream_session.id), headers: { "User-Agent" => user_agent }
      assert_response :success

      doc = Nokogiri::HTML(response.body)
      [
        doc.at_css("meta[property='og:title']")["content"],
        doc.at_css("meta[property='og:description']")["content"],
        doc.at_css("meta[property='og:url']")["content"]
      ]
    end

    assert_equal 1, results.uniq.size
  end

  test "share page bypasses the browser version guard without weakening other pages" do
    outdated_browser =
      "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/109.0.0.0 Mobile Safari/537.36"

    get share_booth_path(@booth, stream: @stream_session.id),
        headers: { "User-Agent" => outdated_browser }

    assert_response :success
    assert_equal @stream_session.title,
                 Nokogiri::HTML(response.body).at_css("meta[property='og:title']")["content"]

    get root_path, headers: { "User-Agent" => outdated_browser }

    assert_response :not_acceptable
  end

  test "staging lets a crawler fetch OGP while returning noindex directives" do
    with_env("APP_ENV" => "staging", "BASIC_AUTH_ENABLED" => "false") do
      get share_booth_path(@booth, stream: @stream_session.id),
          headers: { "User-Agent" => "Twitterbot/1.0" }
    end

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]

    doc = Nokogiri::HTML(response.body)
    assert_equal @stream_session.title, doc.at_css("meta[property='og:title']")["content"]
    assert_equal "summary_large_image", doc.at_css("meta[name='twitter:card']")["content"]
    assert_includes doc.at_css("meta[name='robots']")["content"], "noindex"
  end

  test "dedicated layout does not expose authenticated user or application chrome" do
    customer = User.create!(
      email: "private-sharing-customer@example.com",
      password: "password",
      role: :customer,
      display_name: "非公開確認ユーザー"
    )
    sign_in customer, scope: :user

    get share_booth_path(@booth)

    assert_response :success
    refute_includes response.body, customer.email
    refute_includes response.body, customer.display_name
    assert_select "header", count: 0
    assert_select "footer", count: 0
    assert_select "#modal", count: 0
    assert_select "[data-controller~='ivs-viewer']", count: 0
  end

  test "share descriptions do not use blank or deleted user information" do
    [ " ", nil ].each do |display_name|
      @cast.update!(display_name: display_name, deleted_at: nil)
      get share_booth_path(@booth, stream: @stream_session.id)

      assert_response :success
      assert_equal "ライブ配信をButterflyveで楽しもう",
                   Nokogiri::HTML(response.body).at_css("meta[property='og:description']")["content"]
      refute_includes response.body, @cast.email
    end

    @cast.update!(display_name: "削除済みキャスト", deleted_at: Time.current)
    get share_booth_path(@booth)

    assert_response :success
    assert_equal "ライブ配信をButterflyveで楽しもう",
                 Nokogiri::HTML(response.body).at_css("meta[property='og:description']")["content"]
    refute_includes response.body, @cast.email
    refute_includes response.body, @cast.display_name
  end

  test "attached booth thumbnail OGP variant is emitted as an absolute URL" do
    @booth.thumbnail_image.attach(
      io: File.open(file_fixture("sample.jpg")),
      filename: "sample.jpg",
      content_type: "image/jpeg"
    )

    get share_booth_path(@booth)

    assert_response :success
    image_url = Nokogiri::HTML(response.body).at_css("meta[property='og:image']")["content"]
    assert_match %r{\Ahttps?://}, image_url
    assert_includes image_url, "/rails/active_storage/representations/"
  end

  test "attached booth thumbnail OGP variant is a 1200x630 JPEG under 1 MB" do
    @booth.thumbnail_image.attach(
      io: File.open(file_fixture("thumb.png")),
      filename: "thumb.png",
      content_type: "image/png"
    )

    variant_data = @booth.thumbnail_image.variant(:ogp).processed.download
    image = MiniMagick::Image.read(variant_data)

    assert_equal 1200, image.width
    assert_equal 630, image.height
    assert_equal "JPEG", image.type
    assert_operator variant_data.bytesize, :<, 1.megabyte
  ensure
    image&.destroy!
  end

  test "fallback OGP image is a 1200x630 JPEG under 1 MB" do
    image = MiniMagick::Image.open(Rails.root.join("app/assets/images/booth-share-ogp.jpg"))

    assert_equal 1200, image.width
    assert_equal 630, image.height
    assert_equal "JPEG", image.type
    assert_operator image.size, :<, 1.megabyte
  ensure
    image&.destroy!
  end

  test "sitemap does not include booth sharing URLs" do
    get sitemap_path(format: :xml)

    assert_response :success
    refute_includes response.body, share_booth_url(@booth)
  end
end
