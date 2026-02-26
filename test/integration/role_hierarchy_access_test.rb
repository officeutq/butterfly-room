# frozen_string_literal: true

require "test_helper"

class RoleHierarchyAccessTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @booth1 = Booth.create!(store: @store1, name: "booth1", status: :offline)
    @booth2 = Booth.create!(store: @store2, name: "booth2", status: :offline)

    @customer     = User.create!(email: "customer_h@example.com", password: "password", role: :customer)
    @cast         = User.create!(email: "cast_h@example.com",     password: "password", role: :cast)
    @store_admin  = User.create!(email: "admin_h@example.com",    password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_h@example.com",      password: "password", role: :system_admin)

    # cast は booth1 に所属
    BoothCast.create!(booth: @booth1, cast_user: @cast)

    # store_admin は store1 の admin
    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)
  end

  test "store_admin can access cast namespace (index) and can open own store booth" do
    sign_in @store_admin, scope: :user

    get cast_booths_path
    assert_response :success

    get cast_booth_path(@booth1)
    assert_response :success

    get cast_booth_path(@booth2)
    assert_response :forbidden
  end

  test "cast cannot access admin/system_admin (403)" do
    sign_in @cast, scope: :user

    # admin namespace 入口
    get admin_stores_path
    assert_response :forbidden

    get system_admin_referral_codes_path
    assert_response :forbidden
  end

  test "system_admin can access cast/admin (not forbidden)" do
    sign_in @system_admin, scope: :user

    get cast_booths_path
    assert_response :success

    # 未選択の admin_booths は /admin/stores に誘導される
    get admin_booths_path
    assert_response :redirect
    assert_redirected_to admin_stores_path

    # 選択後は dashboard に戻る
    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect
    assert_redirected_to dashboard_path

    # 選択済みなら admin_booths に入れる
    get admin_booths_path
    assert_response :success
  end

  test "customer cannot access cast/admin/system_admin (403)" do
    sign_in @customer, scope: :user

    get cast_booths_path
    assert_response :forbidden

    get admin_stores_path
    assert_response :forbidden

    get system_admin_referral_codes_path
    assert_response :forbidden
  end
end
