# frozen_string_literal: true

require "test_helper"

class HomeSearchTest < ActionDispatch::IntegrationTest
  def create_user!(email:, role:)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      role: role
    )
  end

  def create_store!(name:)
    Store.create!(name: name)
  end

  def create_booth!(store:, name:, status:, archived_at: nil)
    Booth.create!(
      store: store,
      name: name,
      status: status,
      archived_at: archived_at
    )
  end

  test "qなし: 通常一覧（archivedは出ない）" do
    store1 = create_store!(name: "Alpha Store")
    store2 = create_store!(name: "Beta Store")

    booth_live = create_booth!(store: store1, name: "Rose Booth", status: :live)
    booth_off  = create_booth!(store: store2, name: "Tulip Booth", status: :offline)
    create_booth!(store: store1, name: "Archived Booth", status: :live, archived_at: Time.current)

    customer = create_user!(email: "customer@example.com", role: :customer)
    sign_in customer, scope: :user

    get root_path
    assert_response :success

    assert_includes @response.body, booth_live.name
    assert_includes @response.body, booth_off.name
    refute_includes @response.body, "Archived Booth"
  end

  test "qあり: booth名の部分一致で絞られる" do
    store = create_store!(name: "Alpha Store")
    booth1 = create_booth!(store: store, name: "Rose Booth", status: :live)
    booth2 = create_booth!(store: store, name: "Tulip Booth", status: :offline)

    customer = create_user!(email: "customer2@example.com", role: :customer)
    sign_in customer, scope: :user

    get root_path, params: { q: "Ros" }
    assert_response :success

    assert_includes @response.body, booth1.name
    refute_includes @response.body, booth2.name
  end

  test "qあり: store名の部分一致で絞られる" do
    store1 = create_store!(name: "Alpha Store")
    store2 = create_store!(name: "Beta Store")
    booth1 = create_booth!(store: store1, name: "Rose Booth", status: :live)
    booth2 = create_booth!(store: store2, name: "Tulip Booth", status: :offline)

    customer = create_user!(email: "customer3@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { q: "Alpha" }
    assert_response :success

    assert_includes @response.body, booth1.name
    refute_includes @response.body, booth2.name
  end

  test "archived は検索しても出ない" do
    store = create_store!(name: "Alpha Store")
    create_booth!(store: store, name: "Archived Booth", status: :live, archived_at: Time.current)

    customer = create_user!(email: "customer4@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { q: "Archived" }
    assert_response :success

    refute_includes @response.body, "Archived Booth"
  end

  test "online=1: live/away のみが出る" do
    store = create_store!(name: "Alpha Store")
    booth_live = create_booth!(store: store, name: "Live Booth", status: :live)
    booth_away = create_booth!(store: store, name: "Away Booth", status: :away)
    booth_off  = create_booth!(store: store, name: "Offline Booth", status: :offline)
    booth_standby = create_booth!(store: store, name: "Standby Booth", status: :standby)

    customer = create_user!(email: "customer5@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { online: "1" }
    assert_response :success

    assert_includes @response.body, booth_live.name
    assert_includes @response.body, booth_away.name
    refute_includes @response.body, booth_off.name
    refute_includes @response.body, booth_standby.name
  end

  test "customer のBAN: Homeで予防され、booths#show でも最終拒否される" do
    store = create_store!(name: "Alpha Store")
    booth = create_booth!(store: store, name: "Banned Booth", status: :live)

    customer = create_user!(email: "banned_customer@example.com", role: :customer)
    store_admin = create_user!(email: "store_admin@example.com", role: :store_admin)

    StoreBan.create!(
      store: store,
      customer_user: customer,
      created_by_store_admin_user: store_admin
    )

    login_as(customer, scope: :user)

    get root_path
    assert_response :success
    refute_includes @response.body, booth.name

    get booth_path(booth)
    assert_response :see_other
    assert_redirected_to root_path
  end
end
