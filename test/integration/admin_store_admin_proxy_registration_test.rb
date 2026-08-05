# frozen_string_literal: true

require "test_helper"

class AdminStoreAdminProxyRegistrationTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    @store = Store.create!(name: "Proxy Registration Store")
    @actor = User.create!(email: "proxy-registration-actor@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @actor, membership_role: :admin)
  end

  test "permission holder sees the button and can register a responsible person" do
    UserPermission.create!(user: @actor, permission_type: "store_registration_proxy")
    sign_in @actor, scope: :user
    post admin_current_store_path, params: { store_id: @store.id }

    get admin_store_admin_invitations_path
    assert_response :success
    assert_select "a[href=?]", new_admin_store_admin_proxy_registration_path,
                  text: "店舗責任者を登録（代行用）"

    assert_difference "User.count", 1 do
      assert_difference "StoreMembership.count", 1 do
        post admin_store_admin_proxy_registration_path, params: {
          store_admin_proxy_registration: {
            display_name: "Proxy Responsible",
            email: "proxy-responsible@example.com"
          }
        }
      end
    end

    assert_redirected_to admin_store_admin_invitations_path
    user = User.find_by!(email: "proxy-responsible@example.com")
    assert StoreMembership.admin_only.exists?(store: @store, user: user)
  end

  test "permission is checked on direct access and create" do
    sign_in @actor, scope: :user
    post admin_current_store_path, params: { store_id: @store.id }

    get new_admin_store_admin_proxy_registration_path
    assert_response :forbidden

    assert_no_difference [ "User.count", "StoreMembership.count" ] do
      post admin_store_admin_proxy_registration_path, params: {
        store_admin_proxy_registration: {
          display_name: "Denied",
          email: "denied-responsible@example.com"
        }
      }
    end
    assert_response :forbidden
  end

  test "create revalidates an existing non store_admin" do
    UserPermission.create!(user: @actor, permission_type: "store_registration_proxy")
    customer = User.create!(email: "proxy-existing-customer@example.com", password: "password", role: :customer)
    sign_in @actor, scope: :user
    post admin_current_store_path, params: { store_id: @store.id }

    assert_no_difference [ "User.count", "StoreMembership.count", "ActionMailer::Base.deliveries.size" ] do
      post admin_store_admin_proxy_registration_path, params: {
        store_admin_proxy_registration: {
          display_name: "Wrong Role",
          email: customer.email
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "店舗管理者以外のアカウント"
  end

  test "guest keeps login redirect" do
    get new_admin_store_admin_proxy_registration_path
    assert_redirected_to new_user_session_path
  end
end
