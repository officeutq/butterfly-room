# frozen_string_literal: true

require "test_helper"

class Cast::BoothUpdateTest < ActionDispatch::IntegrationTest
  test "cast booth update redirects to dashboard with notice" do
    cast = User.create!(
      email: "cast_booth_update@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗A")
    booth = Booth.create!(store:, name: "更新前ブース名", description: "更新前説明")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "更新後ブース名",
        description: "更新後説明"
      }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ブースを更新しました"

    booth.reload
    assert_equal "更新後ブース名", booth.name
    assert_equal "更新後説明", booth.description
  end

  test "cast booth update failure redirects to edit for html request" do
    cast = User.create!(
      email: "cast_booth_update_failure@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗B")
    booth = Booth.create!(store:, name: "更新前ブース名", description: "初期説明")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "a" * 101,
        description: "更新後説明"
      }
    }

    assert_redirected_to edit_cast_booth_path(booth)

    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ブース編集"

    booth.reload
    assert_equal "更新前ブース名", booth.name
    assert_equal "初期説明", booth.description
  end

  test "cast booth update failure returns unprocessable_entity for turbo_stream request" do
    cast = User.create!(
      email: "cast_booth_update_failure_turbo@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗C")
    booth = Booth.create!(store:, name: "更新前ブース名", description: "初期説明")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user

    patch cast_booth_path(booth),
          params: {
            booth: {
              name: "a" * 101,
              description: "更新後説明"
            }
          },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "flash_inner"

    booth.reload
    assert_equal "更新前ブース名", booth.name
    assert_equal "初期説明", booth.description
  end

  test "store admin can assign cast to unassigned booth from cast booth edit update" do
    store_admin = User.create!(
      email: "store_admin_assign_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    cast = User.create!(
      email: "assignable_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗D")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store:, user: cast, membership_role: :cast)

    booth = Booth.create!(store:, name: "未紐づけブース", description: "初期説明")

    sign_in store_admin, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "未紐づけブース更新後",
        description: "更新後説明"
      },
      booth_cast: {
        cast_user_id: cast.id
      }
    }

    assert_redirected_to dashboard_path

    booth.reload
    assert_equal "未紐づけブース更新後", booth.name
    assert_equal "更新後説明", booth.description
    assert_equal cast.id, booth.primary_cast_user_id
  end

  test "store admin cannot reassign already assigned booth from cast booth edit update" do
    store_admin = User.create!(
      email: "store_admin_reassign_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    current_cast = User.create!(
      email: "current_assigned_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    other_cast = User.create!(
      email: "other_assignable_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗E")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store:, user: current_cast, membership_role: :cast)
    StoreMembership.create!(store:, user: other_cast, membership_role: :cast)

    booth = Booth.create!(store:, name: "紐づけ済みブース", description: "初期説明")
    BoothCast.create!(booth:, cast_user: current_cast)

    sign_in store_admin, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "変更しようとした名前",
        description: "変更しようとした説明"
      },
      booth_cast: {
        cast_user_id: other_cast.id
      }
    }

    assert_redirected_to edit_cast_booth_path(booth)

    booth.reload
    assert_equal "紐づけ済みブース", booth.name
    assert_equal "初期説明", booth.description
    assert_equal current_cast.id, booth.primary_cast_user_id
  end
end
