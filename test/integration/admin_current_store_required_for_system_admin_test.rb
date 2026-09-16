# frozen_string_literal: true

require "test_helper"

class AdminCurrentStoreRequiredForSystemAdminTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")
    @system_admin = User.create!(email: "sys_guard@example.com", password: "password", role: :system_admin)

    @store_admin = User.create!(email: "admin_guard@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "system_admin with a sole store is automatically selected" do
    sign_in @system_admin, scope: :user

    get admin_booths_path
    assert_response :success
    assert_equal @store.id, session[:current_store_id]
  end

  test "system_admin with invalid current_store_id is corrected and redirected to /admin/stores" do
    sign_in @system_admin, scope: :user

    # いったん選択して session に入れる
    post admin_current_store_path, params: { store_id: @store.id }
    assert_response :redirect
    assert_redirected_to dashboard_path

    # store を削除して session を不正化する
    @store.destroy!

    get admin_booths_path
    assert_response :conflict
    assert_nil session[:current_store_id]
    assert_includes response.body, "管理可能な店舗がありません"
  end

  test "store_admin behavior is not broken (can access admin booths without explicit selection)" do
    sign_in @store_admin, scope: :user

    get admin_booths_path
    assert_response :success
  end
end
