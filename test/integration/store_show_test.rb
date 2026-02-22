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
      business_type: :girls_bar
    )

    # thumbnail attached
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

    # store basic
    assert_includes @response.body, "store"

    # profile
    assert_includes @response.body, "Store description"
    assert_includes @response.body, "渋谷"
    assert_includes @response.body, "ガールズバー"
    assert_includes @response.body, "<img"

    # booths
    assert_includes @response.body, "active"
    assert_includes @response.body, "Cast A"
    assert_includes @response.body, enter_booth_path(active_booth)

    refute_includes @response.body, "archived"
  end
end
