# frozen_string_literal: true

require "test_helper"

class AdminStoresIndexTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @store_admin  = User.create!(email: "admin_idx@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_idx@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)
  end

  test "system_admin sees all stores on /admin/stores" do
    sign_in @system_admin, scope: :user

    get admin_stores_path
    assert_response :success

    assert_select "table tbody tr", count: 2
    assert_select "td", text: @store1.id.to_s
    assert_select "td", text: @store2.id.to_s
  end

  test "store_admin sees only admin membership stores on /admin/stores" do
    sign_in @store_admin, scope: :user

    get admin_stores_path
    assert_response :success

    assert_select "table tbody tr", count: 1
    assert_select "td", text: @store1.id.to_s
    assert_select "td", text: @store2.id.to_s, count: 0
  end

  test "can reach /admin/stores without current_store and selection flow works (store_admin)" do
    sign_in @store_admin, scope: :user

    # current_store 未選択でも /admin/stores に到達できる（選択画面なので）
    get admin_stores_path
    assert_response :success

    # 選択確定（membershipあり）
    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect
    assert_redirected_to dashboard_path

    follow_redirect!
    assert_response :success
  end

  test "can reach /admin/stores without current_store and selection flow works (system_admin)" do
    sign_in @system_admin, scope: :user

    get admin_stores_path
    assert_response :success

    # 選択確定（system_admin は membership 不要）
    post admin_current_store_path, params: { store_id: @store2.id }
    assert_response :redirect
    assert_redirected_to dashboard_path

    follow_redirect!
    assert_response :success

    # 選択中ハイライト（table-active）が付くことを確認（session が反映されている）
    get admin_stores_path
    assert_response :success
    assert_select "tr.table-active td", text: @store2.id.to_s
  end
end
