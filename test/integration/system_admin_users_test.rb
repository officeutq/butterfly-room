# frozen_string_literal: true

require "test_helper"

class SystemAdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @customer     = User.create!(email: "customer_u@example.com", password: "password", role: :customer)
    @store_admin  = User.create!(email: "admin_u@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_u@example.com", password: "password", role: :system_admin)
  end

  test "non system_admin cannot access (403)" do
    sign_in @customer, scope: :user
    get system_admin_users_path
    assert_response :forbidden

    sign_in @store_admin, scope: :user
    get system_admin_users_path
    assert_response :forbidden
  end

  test "system_admin can list/create/update/stop" do
    sign_in @system_admin, scope: :user

    get system_admin_users_path
    assert_response :success

    # create
    assert_difference "User.count", +1 do
      post system_admin_users_path, params: {
        user: { email: "created_u@example.com", password: "password", password_confirmation: "password", role: "customer" }
      }
    end
    assert_response :redirect
    assert_redirected_to system_admin_users_path

    created = User.find_by!(email: "created_u@example.com")
    assert_equal "customer", created.role
    assert_nil created.deleted_at

    # update role/customer -> cast
    patch system_admin_user_path(created), params: { user: { role: "cast" } }
    assert_response :redirect
    assert_redirected_to system_admin_users_path
    assert_equal "cast", created.reload.role

    # stop
    delete system_admin_user_path(created)
    assert_response :redirect
    assert_redirected_to system_admin_users_path
    assert_not_nil created.reload.deleted_at
  end

  test "store_admin role cannot be created nor set (server side)" do
    sign_in @system_admin, scope: :user

    # create with store_admin
    post system_admin_users_path, params: {
      user: { email: "ng_store_admin@example.com", password: "password", password_confirmation: "password", role: "store_admin" }
    }
    assert_response :unprocessable_entity
    assert_nil User.find_by(email: "ng_store_admin@example.com")

    # update to store_admin
    target = User.create!(email: "target_u@example.com", password: "password", role: :customer)
    patch system_admin_user_path(target), params: { user: { role: "store_admin" } }
    assert_response :unprocessable_entity
    assert_equal "customer", target.reload.role
  end

  test "system_admin cannot demote self" do
    sign_in @system_admin, scope: :user

    patch system_admin_user_path(@system_admin), params: { user: { role: "customer" } }
    assert_response :unprocessable_entity
    assert_equal "system_admin", @system_admin.reload.role
  end

  test "cannot demote the last system_admin" do
    sign_in @system_admin, scope: :user

    patch system_admin_user_path(@system_admin), params: { user: { role: "cast" } }
    assert_response :unprocessable_entity
    assert_equal "system_admin", @system_admin.reload.role
  end

  test "can demote another system_admin if at least one remains" do
    other_admin = User.create!(email: "sys_u2@example.com", password: "password", role: :system_admin)

    sign_in @system_admin, scope: :user

    patch system_admin_user_path(other_admin), params: { user: { role: "cast" } }
    assert_response :redirect
    assert_redirected_to system_admin_users_path
    assert_equal "cast", other_admin.reload.role
    assert_equal "system_admin", @system_admin.reload.role
  end

  test "stopped user cannot login" do
    stopped = User.create!(
      email: "stopped_u@example.com",
      password: "password",
      role: :customer,
      deleted_at: Time.current
    )

    post user_session_path, params: { user: { email: stopped.email, password: "password" } }

    # 停止ユーザーは認証不可 → Devise はログイン画面へ戻す（navigational扱いで302になりやすい）
    assert_response :redirect
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success

    # ログインできていないこと（root が未ログイン表示のまま）
    get root_path
    assert_response :success
    assert_select "a", text: "ログイン", href: new_user_session_path
    assert_select "a", text: "新規アカウント作成", href: sign_up_path
  end
end
