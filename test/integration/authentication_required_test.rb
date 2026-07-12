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
    assert_select "a", text: "無料で店舗登録する",
      href: stores_new_registration_path(ref: "0000", from: "stores_lp")
    assert_select "a", text: "お問い合わせはこちら", href: stores_contact_path(from: "stores_lp"), minimum: 1
  end

  test "店舗LPはrefを店舗登録導線へ引き継ぐ" do
    get stores_lp_path(ref: "abc123")

    assert_response :success
    assert_select "a", text: "無料で店舗登録する",
      href: stores_new_registration_path(ref: "abc123", from: "stores_lp")
    assert_select "a", text: "お問い合わせはこちら", href: stores_contact_path(from: "stores_lp"), minimum: 1
  end

  test "未ログインでも外注店舗LP 202607を表示できる" do
    get stores_lp_202607_path

    assert_response :success
    assert_select ".store-lp-202607"
    assert_select "a[href=?]", stores_new_registration_path(from: "stores_lp_202607"), minimum: 1
    assert_select "a[href=?]", stores_contact_path(from: "stores_lp_202607"), minimum: 1
    assert_select "a[href=?]", legal_path, minimum: 1
    assert_select "a[href=?]", payment_services_act_path, minimum: 1
    assert_select "a[href=?]", terms_path, minimum: 1
    assert_select "a[href=?]", privacy_policy_path, minimum: 1
    assert_includes response.body, "お客様に自動返却"
    assert_includes response.body, "今なら、こちらのサイトからの登録で全て無料"
    assert_includes response.body, "お客様の支払い方法は何がありますか？"
    assert_includes response.body, "コンビニ決済、クレジットカード、ApplePay、GooglePay"
    refute_includes response.body, "ファンに自動返却"
    refute_includes response.body, "通常初期費用〇〇円"
  end

  test "外注店舗LP 202607はrefを店舗登録導線へ引き継ぐ" do
    get stores_lp_202607_path(ref: "abc123")

    assert_response :success
    assert_select "a[href=?]", stores_new_registration_path(ref: "abc123", from: "stores_lp_202607"), minimum: 1
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

  test "未ログインでブース視聴ページへアクセス後、ログインすると元のブースへ戻る" do
    store = Store.create!(name: "store-return-to-login")
    booth = Booth.create!(store: store, name: "booth-return-to-login", status: :offline)
    user = User.create!(
      email: "customer-return-to@example.com",
      password: "password",
      role: :customer
    )

    get booth_path(booth)

    assert_redirected_to new_user_session_path

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password"
      }
    }

    assert_redirected_to booth_path(booth)
  end

  test "未ログインでブース視聴ページへアクセス後、顧客新規登録すると元のブースへ戻る" do
    store = Store.create!(name: "store-return-to-sign-up")
    booth = Booth.create!(store: store, name: "booth-return-to-sign-up", status: :offline)

    get booth_path(booth)

    assert_redirected_to new_user_session_path

    post sign_up_path, params: {
      customer_registration: {
        email: "new-customer-return-to@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }

    assert_redirected_to booth_path(booth)
  end
end
