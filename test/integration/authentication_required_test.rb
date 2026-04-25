# frozen_string_literal: true

require "test_helper"

class AuthenticationRequiredTest < ActionDispatch::IntegrationTest
  test "未ログインでもトップページを表示できる" do
    get root_path

    assert_response :success
  end

  test "未ログインでも店舗LPを表示できる" do
    get stores_lp_path

    assert_response :success
  end

  test "未ログインでも通常サインアップページを表示できる" do
    get sign_up_path

    assert_response :success
  end

  test "未ログインでもログインページを表示できる" do
    get new_user_session_path

    assert_response :success
  end

  test "未ログインでも電話番号ログインページを表示できる" do
    get phone_session_path

    assert_response :success
  end

  test "未ログインでもsitemapを表示できる" do
    get sitemap_path(format: :xml)

    assert_response :success
  end

  test "未ログインでdashboardへアクセスするとログインページへリダイレクトされる" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "未ログインでprofile編集へアクセスするとログインページへリダイレクトされる" do
    get edit_profile_path

    assert_redirected_to new_user_session_path
  end

  test "未ログインでfavoritesへアクセスするとログインページへリダイレクトされる" do
    get favorites_booths_path

    assert_redirected_to new_user_session_path
  end

  test "未ログインでwallet購入ページへアクセスするとログインページへリダイレクトされる" do
    get new_wallet_purchase_path

    assert_redirected_to new_user_session_path
  end

  test "未ログインでadminへアクセスするとログインページへリダイレクトされる" do
    get admin_stores_path

    assert_redirected_to new_user_session_path
  end

  test "未ログインでsystem_adminへアクセスするとログインページへリダイレクトされる" do
    get system_admin_users_path

    assert_redirected_to new_user_session_path
  end
end
