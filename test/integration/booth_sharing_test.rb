# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"
require "uri"

class BoothSharingTest < ActionDispatch::IntegrationTest
  setup do
    @tempfiles = []
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

  teardown do
    @tempfiles.each(&:close!)
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
    assert_equal share_ogp_image_booth_url(@booth, format: :jpg), image_url
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
      expected_image_url = share_ogp_image_booth_url(@booth, stream: @stream_session.id, format: :jpg)
      assert_equal @stream_session.title, doc.at_css("meta[property='og:title']")["content"]
      assert_equal expected_url, doc.at_css("meta[property='og:url']")["content"]
      assert_equal expected_url, doc.at_css("link[rel='canonical']")["href"]
      assert_equal expected_image_url, doc.at_css("meta[property='og:image']")["content"]
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
      assert_equal share_ogp_image_booth_url(@booth, format: :jpg),
                   doc.at_css("meta[property='og:image']")["content"]
      refute_includes response.body, other_stream.title
    end
  end

  test "fallback OGP image URL is stable per booth and stream context" do
    second_stream = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :ended,
      title: "二つ目の共有テスト配信",
      started_at: 1.hour.ago,
      ended_at: Time.current,
      started_by_cast_user: @cast
    )

    image_urls = [ @stream_session, second_stream ].map do |stream_session|
      get share_booth_path(@booth, stream: stream_session.id)
      assert_response :success

      Nokogiri::HTML(response.body).at_css("meta[property='og:image']")["content"]
    end

    assert_equal share_ogp_image_booth_url(@booth, stream: @stream_session.id, format: :jpg), image_urls.first
    assert_equal share_ogp_image_booth_url(@booth, stream: second_stream.id, format: :jpg), image_urls.second
    refute_equal image_urls.first, image_urls.second
  end

  test "fallback OGP endpoint publicly serves the common JPEG without conversion" do
    get share_ogp_image_booth_path(@booth, stream: @stream_session.id, format: :jpg),
        headers: { "User-Agent" => "Twitterbot/1.0" }

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_includes response.headers["Content-Disposition"], "inline"
    assert_includes response.headers["Cache-Control"], "public"
    assert_equal File.binread(Rails.root.join("app/assets/images/booth-share-ogp.jpg")), response.body.b
  end

  test "unpublished archived and missing booths return not found" do
    @store.update!(published: false)
    get share_booth_path(@booth)
    assert_response :not_found
    get share_ogp_image_booth_path(@booth, format: :jpg)
    assert_response :not_found

    @store.update!(published: true)
    @booth.update!(archived_at: Time.current)
    get share_booth_path(@booth)
    assert_response :not_found
    get share_ogp_image_booth_path(@booth, format: :jpg)
    assert_response :not_found

    get share_booth_path(id: 0)
    assert_response :not_found
    get share_ogp_image_booth_path(id: 0, format: :jpg)
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

  test "current booth display image is emitted directly as the 1200x630 JPEG OGP" do
    attach_current_image_pair

    get share_booth_path(@booth)

    assert_response :success
    image_url = Nokogiri::HTML(response.body).at_css("meta[property='og:image']")["content"]
    assert_match %r{\Ahttps?://}, image_url
    assert_includes image_url, "/rails/active_storage/blobs/"
    refute_includes image_url, "/rails/active_storage/representations/"
    refute_includes image_url, share_ogp_image_booth_path(@booth)

    image = fetch_image(image_url)
    assert_equal 1200, image.width
    assert_equal 630, image.height
    assert_equal "JPEG", image.type
    assert_equal "image/jpeg", response.media_type
    assert_equal @booth.thumbnail_image.download, response.body.b
  ensure
    image&.destroy!
  end

  test "legacy booth thumbnail keeps a 1200x630 JPEG compatibility OGP" do
    @booth.thumbnail_image.attach(
      io: File.open(file_fixture("thumb.png")),
      filename: "thumb.png",
      content_type: "image/png"
    )

    get share_booth_path(@booth)

    image_url = Nokogiri::HTML(response.body).at_css("meta[property='og:image']")["content"]
    assert_includes image_url, "/rails/active_storage/representations/"
    image = fetch_image(image_url)

    assert_equal 1200, image.width
    assert_equal 630, image.height
    assert_equal "JPEG", image.type
    assert_equal "image/jpeg", response.media_type
    assert_operator response.body.bytesize, :<, 1.megabyte
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

  private

  def attach_current_image_pair
    source = generated_social_jpeg("navy")
    display = generated_social_jpeg("purple")
    @booth.thumbnail_image_source.attach(
      io: source,
      filename: "booth-source.jpg",
      content_type: "image/jpeg",
      identify: false
    )
    @booth.thumbnail_image.attach(
      io: display,
      filename: "booth-display.jpg",
      content_type: "image/jpeg",
      identify: false
    )
    @booth.update!(thumbnail_image_crop_data: {
      "schemaVersion" => 1,
      "ratioKey" => "social",
      "sourceBlobId" => @booth.thumbnail_image_source.blob.id,
      "source" => { "width" => 1200, "height" => 630 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 630 },
      "zoom" => 1.0,
      "output" => {
        "width" => 1200,
        "height" => 630,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    })
  end

  def generated_social_jpeg(color)
    tempfile = Tempfile.new([ "booth-ogp", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("1200x630")
      command << "xc:#{color}"
      command << "JPEG:#{tempfile.path}"
    end
    tempfile.binmode
    tempfile.rewind
    tempfile
  end

  def fetch_image(url)
    uri = URI.parse(url)
    get [ uri.path, uri.query ].compact.join("?")
    3.times do
      break unless response.redirect?

      follow_redirect!
    end
    assert_response :success
    MiniMagick::Image.read(response.body.b)
  end
end
