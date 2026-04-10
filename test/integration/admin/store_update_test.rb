# frozen_string_literal: true

require "test_helper"

class Admin::StoreUpdateTest < ActionDispatch::IntegrationTest
  test "admin store update redirects to dashboard with notice" do
    admin = User.create!(
      email: "admin_store_update@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(
      name: "更新前店舗名",
      description: "更新前概要"
    )

    StoreMembership.create!(
      store:,
      user: admin,
      membership_role: :admin
    )

    sign_in admin, scope: :user

    patch admin_store_path(store), params: {
      store: {
        name: "更新後店舗名",
        description: "更新後概要",
        area: "渋谷",
        business_type: store.business_type
      }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "店舗情報を更新しました"

    store.reload
    assert_equal "更新後店舗名", store.name
    assert_equal "更新後概要", store.description
    assert_equal "渋谷", store.area
  end

  test "admin store update failure redirects to edit for html request" do
    admin = User.create!(
      email: "admin_store_update_failure@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(
      name: "更新前店舗名",
      description: "初期概要"
    )

    StoreMembership.create!(
      store:,
      user: admin,
      membership_role: :admin
    )

    sign_in admin, scope: :user

    patch admin_store_path(store), params: {
      store: {
        name: "",
        description: "更新後概要"
      }
    }

    assert_redirected_to edit_admin_store_path(store)

    follow_redirect!
    assert_response :success
    assert_includes @response.body, "店舗設定"

    store.reload
    assert_equal "更新前店舗名", store.name
    assert_equal "初期概要", store.description
  end

  test "admin store update failure returns unprocessable_entity for turbo_stream request" do
    admin = User.create!(
      email: "admin_store_update_failure_turbo@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(
      name: "更新前店舗名",
      description: "初期概要"
    )

    StoreMembership.create!(
      store:,
      user: admin,
      membership_role: :admin
    )

    sign_in admin, scope: :user

    patch admin_store_path(store),
          params: {
            store: {
              name: "",
              description: "更新後概要"
            }
          },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "flash_inner"

    store.reload
    assert_equal "更新前店舗名", store.name
    assert_equal "初期概要", store.description
  end
end
