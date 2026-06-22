# frozen_string_literal: true

require "test_helper"

class AdminStoreBansTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "admin-store-bans")
    @store_admin = User.create!(email: "admin_store_bans_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "admin_store_bans_system_admin@example.com", password: "password", role: :system_admin)
    @customer = User.create!(email: "admin_store_bans_customer@example.com", password: "password", role: :customer)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "store_admin cannot access or create manual store bans" do
    sign_in @store_admin, scope: :user

    get admin_store_bans_path
    assert_response :forbidden

    assert_no_difference "StoreBan.count" do
      post admin_store_bans_path, params: {
        store_ban: { customer_user_id: @customer.id, reason: "manual" }
      }
    end
    assert_response :forbidden
  end

  test "system_admin can create and revoke manual store ban without physical delete" do
    sign_in @system_admin, scope: :user
    post admin_current_store_path, params: { store_id: @store.id }

    get admin_store_bans_path
    assert_response :success
    assert_select "input[type=number][name='store_ban[customer_user_id]']", count: 0
    assert_select "select[name='store_ban[customer_user_id]']"

    assert_difference "StoreBan.count", 1 do
      post admin_store_bans_path, params: {
        store_ban: { customer_user_id: @customer.id, reason: "manual" }
      }
    end

    ban = StoreBan.find_by!(store: @store, customer_user: @customer)
    assert_nil ban.revoked_at
    assert_equal @system_admin, ban.created_by_store_admin_user

    assert_no_difference "StoreBan.count" do
      delete admin_store_ban_path(ban)
    end

    assert ban.reload.revoked?
    assert_equal @system_admin, ban.revoked_by_user
  end

  test "dashboard hides manual store ban link from store_admin and shows it to system_admin" do
    sign_in @store_admin, scope: :user

    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", admin_store_bans_path, count: 0

    sign_out :user
    sign_in @system_admin, scope: :user
    post admin_current_store_path, params: { store_id: @store.id }

    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", admin_store_bans_path
  end
end
