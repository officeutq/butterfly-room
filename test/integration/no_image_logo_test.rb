# frozen_string_literal: true

require "test_helper"

class NoImageLogoTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "No Image Store", published: true)
    @cast = User.create!(
      email: "no-image-cast@example.com",
      password: "password",
      role: :cast,
      display_name: "No Image Cast"
    )
    @booth = Booth.create!(store: @store, name: "No Image Booth", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)
  end

  test "image placeholders use the common logo on cards" do
    get root_path, params: { mode: "stores" }
    assert_response :success
    assert_no_image_logo ".stores-card-thumbnail-placeholder"

    get root_path, params: { mode: "users" }
    assert_response :success
    assert_no_image_logo ".users-card-thumbnail-placeholder"

    get root_path, params: { mode: "booths" }
    assert_response :success
    assert_no_image_logo ".booths-card-thumbnail-placeholder"
  end

  test "image placeholders use the common logo on heroes" do
    get store_path(@store)
    assert_response :success
    assert_no_image_logo ".store-show-hero-placeholder"

    get user_path(@cast)
    assert_response :success
    assert_no_image_logo ".user-show-hero-placeholder"

    get booth_path(@booth)
    assert_response :success
    assert_no_image_logo ".booth-show-hero-placeholder"

    sign_in @cast, scope: :user
    get cast_booth_path(@booth)
    assert_response :success
    assert_no_image_logo ".booth-show-hero-placeholder"
  end

  private

  def assert_no_image_logo(selector)
    assert_select selector do
      assert_select "img.no-image-logo[src*='no_image_logo'][alt='画像なし']", count: 1
      assert_select "span", text: /no (?:image|thumbnail)/i, count: 0
    end
  end
end
