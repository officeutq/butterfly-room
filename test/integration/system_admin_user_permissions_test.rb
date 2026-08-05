# frozen_string_literal: true

require "test_helper"

class SystemAdminUserPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @system_admin = User.create!(email: "permission-system@example.com", password: "password", role: :system_admin)
    @store_admin = User.create!(email: "permission-target@example.com", password: "password", role: :store_admin)
    @customer = User.create!(email: "permission-general@example.com", password: "password", role: :customer)
  end

  test "only system_admin can access permission management" do
    get system_admin_user_permissions_path
    assert_redirected_to new_user_session_path

    sign_in @store_admin, scope: :user
    get system_admin_user_permissions_path
    assert_response :forbidden
  end

  test "system_admin can grant and delete a permission" do
    sign_in @system_admin, scope: :user

    assert_difference "UserPermission.count", 1 do
      post system_admin_user_permissions_path, params: {
        user_permission: {
          user_email: @store_admin.email,
          permission_type: "store_registration_proxy"
        }
      }
    end

    permission = UserPermission.find_by!(user: @store_admin, permission_type: "store_registration_proxy")
    assert_redirected_to system_admin_user_permissions_path

    get system_admin_user_permissions_path
    assert_response :success
    assert_includes response.body, @store_admin.email
    assert_includes response.body, "店舗責任者の登録代行"

    assert_difference "UserPermission.count", -1 do
      delete system_admin_user_permission_path(permission)
    end
  end

  test "invalid user role and undefined permission are rejected server side" do
    sign_in @system_admin, scope: :user

    assert_no_difference "UserPermission.count" do
      post system_admin_user_permissions_path, params: {
        user_permission: {
          user_email: @customer.email,
          permission_type: "store_registration_proxy"
        }
      }
    end
    assert_response :unprocessable_entity

    assert_no_difference "UserPermission.count" do
      post system_admin_user_permissions_path, params: {
        user_permission: {
          user_email: @store_admin.email,
          permission_type: "undefined"
        }
      }
    end
    assert_response :unprocessable_entity
  end
end
