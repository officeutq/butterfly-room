# frozen_string_literal: true

require "test_helper"

class CustomerSignUpTest < ActionDispatch::IntegrationTest
  test "guest home shows login and sign_up links" do
    get root_path
    assert_response :success

    assert_select "a", text: "ログイン", href: new_user_session_path
    assert_select "a", text: "新規アカウント作成", href: sign_up_path
  end

  test "customer can sign up with role fixed and becomes signed in" do
    email = "new_customer@example.com"

    assert_nil User.find_by(email: email)

    assert_difference "User.count", +1 do
      post sign_up_path, params: {
        customer_registration: {
          email: email,
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    user = User.find_by!(email: email)
    assert_equal "customer", user.role

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes @response.body, email
  end
end
