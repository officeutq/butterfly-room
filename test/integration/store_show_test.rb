# frozen_string_literal: true

require "test_helper"

class StoreShowTest < ActionDispatch::IntegrationTest
  test "guest is redirected to login" do
    store = Store.create!(name: "store")

    get store_path(store)
    assert_response :redirect
    assert_redirected_to new_user_session_path
  end

  test "customer can view store show and see active booths only" do
    store = Store.create!(
      name: "store",
      description: "Store description",
      area: "渋谷",
      business_type: :girls_bar,
      address: "熊本県熊本市中央区本丸1-1",
      phone_number: "090-1111-2222",
      business_hours: "平日 19:00〜1:00",
      website_url: "https://officeutq.co.jp",
      x_url: "https://x.com/Butterflyve_jp",
      instagram_url: "https://www.instagram.com/butterflyve_0315/",
      tiktok_url: "https://www.tiktok.com/@aespa_official",
      youtube_url: "https://www.youtube.com/@SleepRelaxingHealingMusic"
    )

    store.thumbnail.attach(
      io: File.open(Rails.root.join("test/fixtures/files/thumb.png")),
      filename: "thumb.png",
      content_type: "image/png"
    )

    active_booth = Booth.create!(store: store, name: "active", status: :offline)
    Booth.create!(store: store, name: "archived", status: :offline, archived_at: Time.current)

    cast = User.create!(email: "cast@example.com", password: "password", role: :cast, display_name: "Cast A")
    BoothCast.create!(booth: active_booth, cast_user: cast)

    customer = User.create!(email: "customer@example.com", password: "password", role: :customer)
    sign_in customer, scope: :user

    get store_path(store)
    assert_response :success

    assert_includes @response.body, "store"
    assert_includes @response.body, "Store description"
    assert_includes @response.body, "渋谷"
    assert_includes @response.body, "ガールズバー"
    assert_includes @response.body, "熊本県熊本市中央区本丸1-1"
    assert_includes @response.body, "090-1111-2222"
    assert_includes @response.body, "平日 19:00〜1:00"
    assert_includes @response.body, "https://officeutq.co.jp"
    assert_includes @response.body, "<img"

    encoded_address = ERB::Util.url_encode(store.address)
    assert_includes @response.body, "https://www.google.com/maps/search/?api=1&amp;query=#{encoded_address}"
    assert_includes @response.body, "https://officeutq.co.jp"
    assert_includes @response.body, "https://x.com/Butterflyve_jp"
    assert_includes @response.body, "https://www.instagram.com/butterflyve_0315/"
    assert_includes @response.body, "https://www.tiktok.com/@aespa_official"
    assert_includes @response.body, "https://www.youtube.com/@SleepRelaxingHealingMusic"

    assert_includes @response.body, "active"
    assert_includes @response.body, "Cast A"
    assert_includes @response.body, enter_booth_path(active_booth)

    refute_includes @response.body, "archived"
  end

  test "unsafe website url is not linkified" do
    store = Store.create!(
      name: "store",
      website_url: "javascript:alert(1)"
    )

    customer = User.create!(email: "customer2@example.com", password: "password", role: :customer)
    sign_in customer, scope: :user

    get store_path(store)
    assert_response :success

    assert_includes @response.body, "javascript:alert(1)"
    refute_includes @response.body, 'href="javascript:alert(1)"'
  end
end
