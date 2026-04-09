# frozen_string_literal: true

require "test_helper"

class ProfileUpdateTest < ActionDispatch::IntegrationTest
  test "profile update redirects to home with notice" do
    user = User.create!(
      email: "profile_update@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        display_name: "更新後の表示名",
        bio: "更新後の自己紹介"
      }
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "プロフィールを更新しました"

    user.reload
    assert_equal "更新後の表示名", user.display_name
    assert_equal "更新後の自己紹介", user.bio
  end

  test "profile update failure re-renders edit" do
    user = User.create!(
      email: "profile_update_failure@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      bio: "初期bio"
    )

    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        display_name: "更新後の表示名",
        bio: "a" * 501
      }
    }

    assert_response :unprocessable_entity
    assert_includes @response.body, "プロフィール編集"

    user.reload
    assert_not_equal "更新後の表示名", user.display_name
    assert_equal "初期bio", user.bio
  end
end
