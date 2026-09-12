# frozen_string_literal: true

require "test_helper"

class CustomerSignUpTest < ActionDispatch::IntegrationTest
  test "guest welcome shows account and store links without point prices or purchase button" do
    get welcome_path
    assert_response :success

    assert_select ".guest-home" do
      assert_select "a.btn-lg[href=?]", new_user_session_path, text: "ログイン", count: 1
      assert_select "a.btn-lg[href=?]", sign_up_path, text: "視聴者アカウント 新規作成", count: 1
      assert_select "a.btn-lg[href=?]", stores_lp_202609_path, text: "店舗向けサービスを見る", count: 2
      assert_select "a[href=?]", stores_lp_path, count: 0
      assert_select "a", text: "店舗向けページを見る", count: 0
      assert_select "a", text: "ポイントを購入する", count: 0
      assert_select "div", text: /\A[\d,]+pt：[\d,]+円（税込）\z/, count: 0
      assert_select "p", text: "ポイント購入に関して", count: 1
      assert_select "h2", text: "視聴者は、配信をドリンクで応援できます。", count: 1
      assert_select "p", text: "Butterflyveでは、購入したポイントを使ってライブ配信中のキャストへドリンクを送信できます。", count: 1
      assert_select "p", text: "※本サービスは会員制サービスです。ポイントの購入および利用にはログインが必要です。", count: 1
      assert_select "h3", text: "店舗の方へ", count: 1
    end
  end

  test "signed in user is redirected from welcome to the normal home" do
    user = User.create!(email: "welcome-signed-in@example.com", password: "password", role: :customer)
    sign_in user, scope: :user

    get welcome_path

    assert_redirected_to root_path
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

    assert_redirected_to edit_profile_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "プロフィール編集"
    assert_includes @response.body, "アカウントを作成しました。プロフィールを作成してください。"
  end
end
