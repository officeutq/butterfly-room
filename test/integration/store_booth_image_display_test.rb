# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"
require "uri"

class StoreBoothImageDisplayTest < ActionDispatch::IntegrationTest
  setup do
    @tempfiles = []
  end

  teardown do
    @tempfiles.each(&:close!)
  end

  test "cards and heroes use social display attachments and never expose editing sources" do
    store = Store.create!(name: "表示画像店舗", published: true)
    booth = Booth.create!(store:, name: "表示画像ブース", status: :offline)
    cast = create_user("display-image-cast", :cast, display_name: "表示画像キャスト")
    BoothCast.create!(booth:, cast_user: cast)
    attach_social_pair(store, :thumbnail, marker: "store")
    attach_social_pair(booth, :thumbnail, marker: "booth")

    get root_path, params: { mode: "stores" }

    assert_response :success
    assert_select(
      ".stores-card img.stores-card-thumbnail[src*='store-display'][alt='表示画像店舗の店舗画像']",
      count: 1
    )
    assert_not_includes response.body, "store-source"

    get root_path, params: { mode: "booths" }

    assert_response :success
    assert_select(
      ".booths-card img.booths-card-thumbnail[src*='booth-display'][alt='表示画像ブースのブース画像']",
      count: 1
    )
    assert_not_includes response.body, "booth-source"

    get store_path(store)

    assert_response :success
    assert_select(
      ".store-show-hero img.store-show-hero-image[src*='store-display'][alt='表示画像店舗の店舗画像']",
      count: 1
    )
    assert_select ".booths-card img[src*='booth-display']", count: 1
    assert_not_includes response.body, "store-source"
    assert_not_includes response.body, "booth-source"

    get booth_path(booth)

    assert_response :success
    assert_select(
      ".booth-show-hero img.booth-show-hero-image[src*='booth-display'][alt='表示画像ブースのブース画像']",
      count: 1
    )
    assert_not_includes response.body, "booth-source"
  end

  test "admin cards and store and booth selection modals use the social ratio presentation" do
    store = Store.create!(name: "選択画像店舗", published: true)
    second_store = Store.create!(name: "選択画像店舗2", published: true)
    booth = Booth.create!(store:, name: "選択画像ブース", status: :offline)
    second_booth = Booth.create!(store:, name: "選択画像ブース2", status: :offline)
    cast = create_user("selection-image-cast", :cast)
    system_admin = create_user("selection-image-system", :system_admin)
    BoothCast.create!(booth:, cast_user: cast)
    BoothCast.create!(booth: second_booth, cast_user: cast)
    attach_social_pair(store, :thumbnail, marker: "selection-store")
    attach_social_pair(booth, :thumbnail, marker: "selection-booth")

    sign_in system_admin, scope: :user
    post admin_current_store_path, params: { store_id: store.id }
    get admin_booths_path

    assert_response :success
    assert_select ".admin-booths-card-thumbnail-wrap.ratio.ratio-social", count: 2
    assert_select ".admin-booths-card-thumbnail[alt='選択画像ブースのブース画像']", count: 1

    get select_modal_admin_stores_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select ".store-select-thumbnail[src*='selection-store'][alt='選択画像店舗の店舗画像']", count: 1
    assert_select "[style*='aspect-ratio: 40 / 21']", minimum: 1

    sign_out system_admin
    sign_in cast, scope: :user
    get cast_booths_path

    assert_response :success
    assert_select ".cast-booths-card-thumbnail-wrap.ratio.ratio-social", count: 2
    assert_select ".cast-booths-card-thumbnail[alt='選択画像ブースのブース画像']", count: 1

    get select_modal_cast_booths_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select ".booth-select-thumbnail[src*='selection-booth'][alt='選択画像ブースのブース画像']", count: 1
    assert_select "[style*='aspect-ratio: 40 / 21']", minimum: 1
    assert_not_includes response.body, "selection-booth-source"
  end

  test "home store and booth cards preload display attachments and blobs" do
    3.times do |index|
      store = Store.create!(name: "事前読込店舗#{index}", published: true)
      booth = Booth.create!(store:, name: "事前読込ブース#{index}", status: :offline)
      cast = create_user("preload-image-cast-#{index}", :cast)
      BoothCast.create!(booth:, cast_user: cast)
      attach_fixture(store.thumbnail, "store-preload-#{index}.jpg")
      attach_fixture(booth.thumbnail_image, "booth-preload-#{index}.jpg")
    end

    store_queries = capture_active_storage_queries do
      get root_path, params: { mode: "stores" }
    end
    assert_response :success
    assert_operator store_queries.length, :<=, 3, store_queries.join("\n")
    assert_equal 0, lazy_active_storage_query_count(store_queries), store_queries.join("\n")

    booth_queries = capture_active_storage_queries do
      get root_path, params: { mode: "booths" }
    end
    assert_response :success
    assert_operator booth_queries.length, :<=, 3, booth_queries.join("\n")
    assert_equal 0, lazy_active_storage_query_count(booth_queries), booth_queries.join("\n")
  end

  test "store OGP uses the display image or the common 1200x630 JPEG fallback" do
    store = Store.create!(name: "OGP画像店舗", published: true)
    attach_social_pair(store, :thumbnail, marker: "store-ogp")

    get store_path(store)

    assert_response :success
    image_url = Nokogiri::HTML(response.body).at_css("meta[property='og:image']")["content"]
    assert_includes image_url, "store-ogp-display"
    image = fetch_image(image_url)
    assert_equal [ 1200, 630, "JPEG" ], [ image.width, image.height, image.type ]
    assert_equal "image/jpeg", response.media_type

    store.thumbnail.purge
    get store_path(store)

    fallback_url = Nokogiri::HTML(response.body).at_css("meta[property='og:image']")["content"]
    assert_includes fallback_url, "booth-share-ogp"
    fallback = fetch_image(fallback_url)
    assert_equal [ 1200, 630, "JPEG" ], [ fallback.width, fallback.height, fallback.type ]
    assert_equal "image/jpeg", response.media_type
  ensure
    image&.destroy!
    fallback&.destroy!
  end

  private

  def create_user(prefix, role, **attributes)
    User.create!({
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role:
    }.merge(attributes))
  end

  def attach_social_pair(record, purpose, marker:)
    configuration = record.image_attachment_purpose_for(purpose)
    source = record.public_send(configuration.source_attachment)
    display = record.public_send(configuration.display_attachment)
    attach_generated(source, "#{marker}-source.jpg", color: "navy")
    attach_generated(display, "#{marker}-display.jpg", color: "purple")
    record.update!(configuration.crop_attribute => {
      "schemaVersion" => 1,
      "ratioKey" => "social",
      "sourceBlobId" => source.blob.id,
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

  def attach_generated(attachment, filename, color:)
    tempfile = Tempfile.new([ "social-display", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("1200x630")
      command << "xc:#{color}"
      command << "JPEG:#{tempfile.path}"
    end
    tempfile.binmode
    tempfile.rewind
    attachment.attach(io: tempfile, filename:, content_type: "image/jpeg", identify: false)
  end

  def attach_fixture(attachment, filename)
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      attachment.attach(io:, filename:, content_type: "image/jpeg", identify: false)
    end
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

  def capture_active_storage_queries
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached] || payload[:name] == "SCHEMA"
      next unless sql.include?("active_storage_attachments") || sql.include?("active_storage_blobs")

      queries << sql
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      ActiveRecord::Base.uncached { yield }
    end
    queries
  end

  def lazy_active_storage_query_count(queries)
    queries.count do |sql|
      sql.start_with?('SELECT "active_storage_attachments".*') &&
        sql.include?('"active_storage_attachments"."record_id" =')
    end
  end
end
