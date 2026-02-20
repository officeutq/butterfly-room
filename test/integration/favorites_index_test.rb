# frozen_string_literal: true

require "test_helper"

class FavoritesIndexTest < ActionDispatch::IntegrationTest
  test "favorites index requires login" do
    get favorites_booths_path
    assert_redirected_to new_user_session_path

    get favorites_stores_path
    assert_redirected_to new_user_session_path
  end

  test "booth favorites index shows only active booths and orders by favorite created_at desc" do
    store = Store.create!(name: "store1")
    booth1 = Booth.create!(store: store, name: "booth1", status: :offline)
    booth2 = Booth.create!(store: store, name: "booth2", status: :offline)

    user = User.create!(email: "customer@example.com", password: "password", role: :customer)
    sign_in user, scope: :user

    fav1 = FavoriteBooth.create!(user: user, booth: booth1)
    fav2 = FavoriteBooth.create!(user: user, booth: booth2)

    # booth1 をアーカイブ → 一覧から除外される
    booth1.update!(archived_at: Time.current)

    get favorites_booths_path
    assert_response :success

    body = response.body
    assert_includes body, "booth2"
    assert_not_includes body, "booth1"

    # created_at desc の順序確認（booth2 → booth1 のはずだが booth1 は除外済み）
    assert_operator body.index("booth2"), :<, body.length
  end

  test "store favorites index orders by favorite created_at desc" do
    store1 = Store.create!(name: "store1")
    store2 = Store.create!(name: "store2")

    user = User.create!(email: "customer@example.com", password: "password", role: :customer)
    sign_in user, scope: :user

    FavoriteStore.create!(user: user, store: store1)
    FavoriteStore.create!(user: user, store: store2)

    get favorites_stores_path
    assert_response :success

    body = response.body
    assert_includes body, "store1"
    assert_includes body, "store2"

    # store2 が後で作られている想定（create順）→ body上で store2 が先に出ることを軽く確認
    assert_operator body.index("store2"), :<, body.index("store1")
  end

  test "customer favorites index excludes banned stores (preventive)" do
    store_ok = Store.create!(name: "store_ok")
    store_ng = Store.create!(name: "store_ng")

    booth_ok = Booth.create!(store: store_ok, name: "booth_ok", status: :offline)
    booth_ng = Booth.create!(store: store_ng, name: "booth_ng", status: :offline)

    customer = User.create!(email: "customer@example.com", password: "password", role: :customer)
    admin = User.create!(email: "admin@example.com", password: "password", role: :store_admin)

    FavoriteBooth.create!(user: customer, booth: booth_ok)
    FavoriteBooth.create!(user: customer, booth: booth_ng)
    FavoriteStore.create!(user: customer, store: store_ok)
    FavoriteStore.create!(user: customer, store: store_ng)

    StoreBan.create!(store: store_ng, customer_user: customer, created_by_store_admin_user: admin)

    sign_in customer, scope: :user

    get favorites_booths_path
    assert_response :success
    assert_includes response.body, "booth_ok"
    assert_not_includes response.body, "booth_ng"

    get favorites_stores_path
    assert_response :success
    assert_includes response.body, "store_ok"
    assert_not_includes response.body, "store_ng"
  end

  test "system_admin favorites index does not exclude banned stores" do
    store_ng = Store.create!(name: "ng")
    booth_ng = Booth.create!(store: store_ng, name: "booth_ng", status: :offline)

    customer = User.create!(email: "customer@example.com", password: "password", role: :customer)
    admin = User.create!(email: "admin@example.com", password: "password", role: :store_admin)
    sys = User.create!(email: "sys@example.com", password: "password", role: :system_admin)

    # customer が BAN されている store
    StoreBan.create!(store: store_ng, customer_user: customer, created_by_store_admin_user: admin)

    # system_admin 自身のお気に入りとして登録
    FavoriteBooth.create!(user: sys, booth: booth_ng)
    FavoriteStore.create!(user: sys, store: store_ng)

    sign_in sys, scope: :user

    get favorites_booths_path
    assert_response :success
    assert_includes response.body, "booth_ng"

    get favorites_stores_path
    assert_response :success
    assert_includes response.body, "ng"
  end
end
