# frozen_string_literal: true

require "test_helper"

class PasswordResetEditTest < ActionDispatch::IntegrationTest
  setup do
    @target = User.create!(email: "password-target@example.com", password: "old-password", role: :store_admin)
    @other_user = User.create!(email: "password-other@example.com", password: "other-password", role: :customer)
  end

  test "guest can open a valid password setup URL" do
    token = @target.send(:set_reset_password_token)

    get edit_user_password_path(reset_password_token: token)

    assert_response :success
    assert_select "input[name='user[reset_password_token]'][value=?]", token
  end

  test "signed in target user is signed out and can open the password setup form" do
    token = @target.send(:set_reset_password_token)
    sign_in @target, scope: :user

    get edit_user_password_path(reset_password_token: token)

    assert_response :success
    assert_select "input[name='user[reset_password_token]'][value=?]", token

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "a different signed in user is signed out and the token target form is shown" do
    token = @target.send(:set_reset_password_token)
    sign_in @other_user, scope: :user

    get edit_user_password_path(reset_password_token: token)

    assert_response :success
    assert_select "input[name='user[reset_password_token]'][value=?]", token

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "guest can open the password email resend page from a tokenized link" do
    token = @target.send(:set_reset_password_token)

    get new_user_password_path(reset_password_token: token)

    assert_response :success
    assert_select "form[action=?]", user_password_path
  end

  test "signed in target user is signed out before the password email resend page is shown" do
    token = @target.send(:set_reset_password_token)
    sign_in @target, scope: :user

    get new_user_password_path(reset_password_token: token)

    assert_response :success
    assert_select "form[action=?]", user_password_path

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "a different signed in user is signed out for an expired tokenized resend link" do
    token = @target.send(:set_reset_password_token)
    sign_in @other_user, scope: :user

    travel 7.hours do
      get new_user_password_path(reset_password_token: token)
    end

    assert_response :success
    assert_select "form[action=?]", user_password_path

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "an invalid resend token does not sign out the current user" do
    sign_in @other_user, scope: :user

    get new_user_password_path(reset_password_token: "invalid-token")

    assert_redirected_to root_path
    assert_equal I18n.t("devise.failure.already_authenticated"), flash[:alert]

    get dashboard_path
    assert_response :success
  end

  test "target user can set a new password and sign in with it" do
    token = @target.send(:set_reset_password_token)
    get edit_user_password_path(reset_password_token: token)

    patch user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "new-password",
        password_confirmation: "new-password"
      }
    }

    assert_response :redirect
    assert @target.reload.valid_password?("new-password")

    sign_out :user
    post user_session_path, params: {
      user: { email: @target.email, password: "new-password" }
    }
    assert_response :redirect

    get dashboard_path
    assert_response :success
  end

  test "invalid and expired tokens cannot change the password" do
    patch user_password_path, params: {
      user: {
        reset_password_token: "invalid-token",
        password: "invalid-new-password",
        password_confirmation: "invalid-new-password"
      }
    }

    assert_response :unprocessable_entity
    assert @target.reload.valid_password?("old-password")

    token = @target.send(:set_reset_password_token)
    travel 7.hours do
      patch user_password_path, params: {
        user: {
          reset_password_token: token,
          password: "expired-new-password",
          password_confirmation: "expired-new-password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert @target.reload.valid_password?("old-password")
  end

  test "signed in user without a token keeps the existing already authenticated behavior" do
    sign_in @other_user, scope: :user

    get edit_user_password_path

    assert_redirected_to root_path
    assert_equal I18n.t("devise.failure.already_authenticated"), flash[:alert]

    get dashboard_path
    assert_response :success
  end

  test "signed in user without a token keeps the existing password request behavior" do
    sign_in @other_user, scope: :user

    get new_user_password_path

    assert_redirected_to root_path
    assert_equal I18n.t("devise.failure.already_authenticated"), flash[:alert]

    get dashboard_path
    assert_response :success
  end
end
