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
end
