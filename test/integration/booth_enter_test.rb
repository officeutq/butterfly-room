# frozen_string_literal: true

require "test_helper"

class BoothEnterTest < ActionDispatch::IntegrationTest
  def create_store!(name: "store")
    Store.create!(name: name)
  end

  def create_booth!(store:, name: "booth", status: :offline)
    Booth.create!(store: store, name: name, status: status)
  end

  test "guest: enter redirects to booth show" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :offline)

    get enter_booth_path(booth)
    assert_response :redirect
    assert_redirected_to booth_path(booth)
  end

  test "customer: enter redirects to booth show" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :offline)

    customer = User.create!(email: "customer_enter@example.com", password: "password", role: :customer)
    sign_in customer, scope: :user

    get enter_booth_path(booth)
    assert_response :redirect
    assert_redirected_to booth_path(booth)
  end

  test "cast (own booth): enter redirects to cast live and sets session" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :standby)

    cast = User.create!(email: "cast_enter@example.com", password: "password", role: :cast)
    BoothCast.create!(booth: booth, cast_user: cast)

    sign_in cast, scope: :user

    get enter_booth_path(booth)
    assert_response :redirect
    assert_redirected_to live_cast_booth_path(booth)

    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]
  end

  test "cast (other booth): enter redirects to booth show" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :offline)

    cast = User.create!(email: "cast_other@example.com", password: "password", role: :cast)
    sign_in cast, scope: :user

    get enter_booth_path(booth)
    assert_response :redirect
    assert_redirected_to booth_path(booth)
  end

  test "store_admin (own store): enter renders selection page" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :offline)

    admin = User.create!(email: "admin_enter@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    get enter_booth_path(booth)
    assert_response :success
    assert_includes response.body, "視聴する"
    assert_includes response.body, "配信する"
  end

  test "system_admin: enter renders selection page" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :offline)

    sys = User.create!(email: "sys_enter@example.com", password: "password", role: :system_admin)
    sign_in sys, scope: :user

    get enter_booth_path(booth)
    assert_response :success
    assert_includes response.body, "視聴する"
    assert_includes response.body, "配信する"
  end

  test "enter_as_cast: store_admin can start (sets session and redirects)" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b", status: :standby)

    admin = User.create!(email: "admin_enter_as_cast@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    post enter_as_cast_booth_path(booth)
    assert_response :redirect
    assert_redirected_to live_cast_booth_path(booth)

    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]
  end
end
