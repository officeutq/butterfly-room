# frozen_string_literal: true

require "test_helper"

class AdminStoreSelectionReturnTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")

    @system_admin = User.create!(email: "sys_rt@example.com", password: "password", role: :system_admin)

    @store_admin = User.create!(email: "admin_rt@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "return_to: selecting store redirects back to the admin page" do
    sign_in @store_admin, scope: :user

    get admin_stores_path(return_to: admin_booths_path)
    assert_response :success

    post admin_current_store_path, params: { store_id: @store.id, return_to: admin_booths_path }
    assert_response :redirect
    assert_redirected_to admin_booths_path
  end

  test "return_to_key: payout_account_edit redirects to the current_store scoped page" do
    sign_in @system_admin, scope: :user

    get admin_stores_path(return_to_key: "payout_account_edit")
    assert_response :success

    post admin_current_store_path, params: { store_id: @store.id, return_to_key: "payout_account_edit" }
    assert_response :redirect
    assert_redirected_to edit_admin_payout_account_path
  end

  test "invalid return_to is rejected and falls back to dashboard" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store.id, return_to: "//evil.example.com" }
    assert_response :redirect
    assert_redirected_to dashboard_path
  end
end
