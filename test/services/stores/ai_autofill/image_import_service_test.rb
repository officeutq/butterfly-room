# frozen_string_literal: true

require "test_helper"

class Stores::AiAutofill::ImageImportServiceTest < ActiveSupport::TestCase
  Importer = Stores::AiAutofill::ImageImportService
  Sources = Stores::AiAutofill::ImageSources
  Fetcher = Stores::AiAutofill::PublicImageFetcher
  Identity = Data.define(:id)
  FakeFetcher = Struct.new(:pages, :calls) do
    def call(url, **options)
      calls << [ url, options ]
      result = pages.fetch(url) { raise Fetcher::Error, "http_403" }
      raise result if result.is_a?(Exception)

      result
    end
  end

  setup do
    @store = Identity.new(id: 1)
    @actor = Identity.new(id: 2)
    @sources = Sources::FIELDS.zip(Sources::LABELS).map do |field, title|
      { "kind" => field, "title" => title, "url" => "https://#{field}.example/shop" }
    end
    @pages = {}
    @calls = []
  end

  test "fetches representative images in source order and skips inaccessible, tiny and corrupt images" do
    page(0, '<meta property="og:image" content="/tiny.jpg">')
    @pages["https://website_url.example/tiny.jpg"] = image(File.binread(Rails.root.join("test/fixtures/files/sample.jpg")))
    # X returns 403. Instagram is not a usable image. TikTok's metadata supplies a CDN image.
    page(2, '<meta property="og:image" content="https://cdn.example/broken">')
    @pages["https://cdn.example/broken"] = image("<html>Login required</html>")
    page(3, '<meta name="twitter:image" content="https://cdn.example/store.jpg">')
    bytes = jpeg_bytes
    @pages["https://cdn.example/store.jpg"] = image(bytes)
    importer = build_importer
    result = importer.call

    assert_equal "tiktok_url", result.source["kind"]
    assert_equal bytes, result.bytes
    assert_equal "image/jpeg", result.content_type
    assert_equal %w[website_url x_url instagram_url tiktok_url], importer.attempts.pluck(:kind)
    assert_not @calls.any? { |url, _| url.include?("youtube_url") }
    assert_equal [ 1.megabyte, 5.megabytes ], @calls.first(2).map { |_, options| options[:max_bytes] }
  end

  test "uses OG before Twitter Card and never scrapes arbitrary image tags" do
    page(0, '<img src="/unrelated.jpg"><meta name="twitter:image" content="/twitter.jpg"><meta property="og:image" content="/og.jpg">')
    @pages["https://website_url.example/og.jpg"] = image(jpeg_bytes)
    assert_equal "website_url", build_importer.call.source["kind"]
    assert_equal [ @sources[0]["url"], "https://website_url.example/og.jpg" ], @calls.map(&:first)
  end

  test "all failures return no image and page redirects cannot change the store or account" do
    page(0, "<html><img src='/arbitrary.jpg'></html>")
    importer = build_importer
    assert_nil importer.call
    assert_equal 5, importer.attempts.size
    redirect_guard = @calls.first.last.fetch(:allowed_redirect)
    assert redirect_guard.call("https://www.website_url.example/shop/")
    assert_not redirect_guard.call("https://website_url.example/login")
    assert_not redirect_guard.call("https://website_url.example/another-shop")
    assert_not redirect_guard.call("https://other.example/shop")
  end

  test "invalid or expired tokens never trigger an external fetch" do
    assert_raises(Importer::InvalidToken) { build_importer(token: "forged").call }
    assert_empty @calls
  end

  test "a social login shell or another account's metadata is never imported" do
    page(1, '<meta property="og:url" content="https://x_url.example/login"><meta property="og:image" content="https://cdn.example/logo.jpg">')
    importer = build_importer
    assert_nil importer.call
    assert_includes importer.attempts, { kind: "x_url", status: "page_identity_missing" }
    assert_not @calls.any? { |url, _| url == "https://cdn.example/logo.jpg" }
  end

  private

  def build_importer(token: Sources.token_for(@sources, store: @store, actor: @actor))
    Importer.new(store: @store, actor: @actor, token:, fetcher: FakeFetcher.new(@pages, @calls))
  end

  def page(index, body)
    url = @sources[index]["url"]
    body += "<meta property='og:url' content='#{url}'>" unless body.include?("og:url")
    @pages[url] = Fetcher::Result.new(body:, content_type: "text/html", url:)
  end

  def image(body)
    Fetcher::Result.new(body:, content_type: "image/jpeg", url: "https://cdn.example/image.jpg")
  end

  def jpeg_bytes
    Tempfile.create([ "store-image-test", ".jpg" ]) do |file|
      MiniMagick.convert do |command|
        command.size("640x400")
        command << "xc:purple"
        command << "JPEG:#{file.path}"
      end
      File.binread(file.path)
    end
  end
end
