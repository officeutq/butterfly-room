# frozen_string_literal: true

require "test_helper"

class AdminStoreEditAuthorizationTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess

  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @customer     = User.create!(email: "cust_s@example.com", password: "password", role: :customer)
    @store_admin  = User.create!(email: "admin_s@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_s@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)
  end

  test "customer cannot edit/update (403)" do
    sign_in @customer, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :forbidden

    patch admin_store_path(@store1), params: { store: { name: "x" } }
    assert_response :forbidden
  end

  test "store_admin can edit/update only own store (403 for others)" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :success

    get edit_admin_store_path(@store2)
    assert_response :forbidden

    patch admin_store_path(@store2), params: { store: { name: "x" } }
    assert_response :forbidden
  end

  test "system_admin can edit/update any store" do
    sign_in @system_admin, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :success

    patch admin_store_path(@store2), params: { store: { name: "sys updated" } }
    assert_response :redirect
    assert_redirected_to dashboard_path
    assert_equal "sys updated", @store2.reload.name
  end

  test "store_admin can update fields and attach thumbnail" do
    sign_in @store_admin, scope: :user

    file = fixture_file_upload(Rails.root.join("test/fixtures/files/thumb.png"), "image/png")

    patch admin_store_path(@store1), params: {
      store: {
        name: "store1 updated",
        description: "desc",
        area: "渋谷",
        business_type: "girls_bar",
        thumbnail: file
      }
    }

    assert_response :redirect
    assert_redirected_to dashboard_path

    @store1.reload
    assert_equal "store1 updated", @store1.name
    assert_equal "desc", @store1.description
    assert_equal "渋谷", @store1.area
    assert_equal "girls_bar", @store1.business_type
    assert @store1.thumbnail.attached?
  end

  test "store_admin can update basic info fields" do
    sign_in @store_admin, scope: :user

    result = Struct.new(:latitude, :longitude, :coordinates).new(
      32.8061463,
      130.7058304,
      [32.8061463, 130.7058304]
    )

    original_search = Geocoder.method(:search)

    Geocoder.define_singleton_method(:search) do |*_args|
      [ result ]
    end

    patch admin_store_path(@store1), params: {
      store: {
        name: "store1 updated",
        description: "desc",
        area: "渋谷",
        business_type: "girls_bar",
        address: "熊本県熊本市中央区本丸1-1",
        phone_number: "090-1111-2222",
        business_hours: "平日 19:00〜1:00",
        website_url: "https://officeutq.co.jp",
        x_url: "https://x.com/Butterflyve_jp",
        instagram_url: "https://www.instagram.com/butterflyve_0315/",
        tiktok_url: "https://www.tiktok.com/@aespa_official",
        youtube_url: "https://www.youtube.com/@SleepRelaxingHealingMusic"
      }
    }

    assert_response :redirect
    assert_redirected_to dashboard_path

    @store1.reload
    assert_equal "store1 updated", @store1.name
    assert_equal "desc", @store1.description
    assert_equal "渋谷", @store1.area
    assert_equal "girls_bar", @store1.business_type
    assert_equal "熊本県熊本市中央区本丸1-1", @store1.address
    assert_equal "090-1111-2222", @store1.phone_number
    assert_equal "平日 19:00〜1:00", @store1.business_hours
    assert_equal "https://officeutq.co.jp", @store1.website_url
    assert_equal "https://x.com/Butterflyve_jp", @store1.x_url
    assert_equal "https://www.instagram.com/butterflyve_0315/", @store1.instagram_url
    assert_equal "https://www.tiktok.com/@aespa_official", @store1.tiktok_url
    assert_equal "https://www.youtube.com/@SleepRelaxingHealingMusic", @store1.youtube_url
    assert_not_nil @store1.latitude
    assert_not_nil @store1.longitude
  ensure
    Geocoder.define_singleton_method(:search, original_search)
  end
end
