# frozen_string_literal: true

require "test_helper"

class AdminProxyStoreRegistrationTest < ActionDispatch::IntegrationTest
  setup do
    @referral_code = ReferralCode.create!(code: "PROXY-INTEGRATION", enabled: true, expires_at: 1.day.from_now)
    @actor = User.create!(email: "proxy-integration@example.com", password: "password", role: :store_admin)
  end

  test "permission holder can create and switch to a proxy store" do
    UserPermission.create!(user: @actor, permission_type: "store_registration_proxy")
    sign_in @actor, scope: :user

    get new_admin_store_path
    assert_response :success

    assert_no_difference "User.count" do
      post admin_stores_path, params: {
        proxy_store_registration: {
          store_name: "Created Proxy Store",
          referral_code: @referral_code.code
        }
      }
    end

    store = Store.find_by!(name: "Created Proxy Store")
    assert_redirected_to edit_admin_store_path(store)
    assert_equal store.id, session[:current_store_id].to_i
    assert_nil session[:current_booth_id]
    assert StoreMembership.admin_only.exists?(store: store, user: @actor)
  end

  test "users without the additional permission and system_admin are forbidden" do
    sign_in @actor, scope: :user
    get new_admin_store_path
    assert_response :forbidden

    system_admin = User.create!(email: "proxy-system@example.com", password: "password", role: :system_admin)
    sign_in system_admin, scope: :user
    get new_admin_store_path
    assert_response :forbidden
  end

  test "guest keeps the existing login redirect" do
    get new_admin_store_path
    assert_redirected_to new_user_session_path
  end
end
