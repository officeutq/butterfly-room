# frozen_string_literal: true

require "test_helper"
require "uri"

class UserCoverDisplayTest < ActionDispatch::IntegrationTest
  test "cards profile and sharing metadata use cover instead of avatar" do
    user = create_user("cover-display", :cast, display_name: "Cover Display User", bio: "Cover profile bio")
    attach_image(user.avatar, "avatar-marker.png", "thumb.png", "image/png")
    attach_image(user.cover_image, "cover-marker.jpg", "sample.jpg", "image/jpeg")

    get root_path, params: { mode: "users" }

    assert_response :success
    assert_select(
      ".users-card img.users-card-thumbnail[src*='cover-marker']" \
      "[alt='Cover Display Userのカバー画像']",
      count: 1
    )
    assert_select ".users-card img.users-card-thumbnail[src*='avatar-marker']", count: 0

    get user_path(user)

    assert_response :success
    assert_select(
      ".user-show-hero img.user-show-hero-image[src*='cover-marker']" \
      "[alt='Cover Display Userのカバー画像']",
      count: 1
    )
    assert_select ".user-show-hero img[src*='avatar-marker']", count: 0
    document = Nokogiri::HTML(response.body)
    assert_equal "Cover Display User | Butterflyve（バタフライブ）", document.at_css("meta[property='og:title']")["content"]
    assert_equal "Cover profile bio", document.at_css("meta[property='og:description']")["content"]
    assert_equal "profile", document.at_css("meta[property='og:type']")["content"]
    assert_equal user_url(user), document.at_css("meta[property='og:url']")["content"]
    assert_equal user_url(user), document.at_css("link[rel='canonical']")["href"]
    assert_nil document.at_css("meta[name='robots']")
    image_url = document.at_css("meta[property='og:image']")["content"]
    assert_includes image_url, "cover-marker"
    assert_equal image_url, document.at_css("meta[name='twitter:image']")["content"]

    get_image_url(image_url)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal user.cover_image.download, response.body.b
  end

  test "missing cover uses the common logo even when avatar exists" do
    user = create_user("cover-fallback", :cast, display_name: "Cover Fallback User")
    attach_image(user.avatar, "avatar-only.png", "thumb.png", "image/png")

    get root_path, params: { mode: "users" }

    assert_response :success
    assert_select ".users-card-thumbnail-placeholder img.no-image-logo[src*='no_image_logo']", count: 1
    assert_select ".users-card img[src*='avatar-only']", count: 0

    get user_path(user)

    assert_response :success
    assert_select ".user-show-hero-placeholder img.no-image-logo[src*='no_image_logo']", count: 1
    assert_select ".user-show-hero img[src*='avatar-only']", count: 0
    document = Nokogiri::HTML(response.body)
    image_url = document.at_css("meta[property='og:image']")["content"]
    assert_match %r{\Ahttps?://}, image_url
    assert_includes image_url, "no_image_logo"
    assert_equal image_url, document.at_css("meta[name='twitter:image']")["content"]

    get_image_url(image_url)
    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "non public profile visible to the signed in user is noindex" do
    customer = create_user("cover-private", :customer, display_name: "Private Profile")
    sign_in customer, scope: :user

    get user_path(customer)

    assert_response :success
    document = Nokogiri::HTML(response.body)
    robots = document.at_css("meta[name='robots']")["content"].split(",").map(&:strip)
    assert_includes robots, "noindex"
    assert_includes robots, "nofollow"
  end

  test "home and favorites preload cover attachments and blobs" do
    customer = create_user("cover-query-customer", :customer)
    users = 3.times.map do |index|
      create_user("cover-query-#{index}", :cast, display_name: "Cover Query #{index}").tap do |user|
        attach_image(user.cover_image, "cover-query-#{index}.jpg", "sample.jpg", "image/jpeg")
      end
    end

    home_queries = capture_active_storage_queries do
      get root_path, params: { mode: "users" }
    end
    assert_response :success
    assert_operator home_queries.length, :<=, 3, home_queries.join("\n")
    assert_equal 0, lazy_active_storage_query_count(home_queries), home_queries.join("\n")

    users.each { |user| customer.favorite_users.create!(target_user: user) }
    sign_in customer, scope: :user
    favorite_queries = capture_active_storage_queries do
      get favorites_users_path
    end
    assert_response :success
    assert_operator favorite_queries.length, :<=, 3, favorite_queries.join("\n")
    # 等価条件の1件はログイン中ユーザーのヘッダーアバターであり、
    # 3件のカード用カバーは2本のIN preload queryに収まる。
    assert_operator lazy_active_storage_query_count(favorite_queries), :<=, 1, favorite_queries.join("\n")
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

  def attach_image(attachment, filename, fixture, content_type)
    File.open(file_fixture(fixture), "rb") do |io|
      attachment.attach(io:, filename:, content_type:, identify: false)
    end
  end

  def get_image_url(url)
    uri = URI.parse(url)
    get [ uri.path, uri.query ].compact.join("?")
    3.times do
      break unless response.redirect?

      follow_redirect!
    end
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
