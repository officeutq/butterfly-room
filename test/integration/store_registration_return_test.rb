# frozen_string_literal: true

require "test_helper"

class StoreRegistrationReturnTest < ActionDispatch::IntegrationTest
  test "new registration falls back to current store LP when from is missing" do
    get stores_new_registration_path(ref: "1001")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path
    assert_select "a[href=?]", stores_lp_path, text: "戻る"
  end

  test "new registration keeps back link for current store LP" do
    get stores_new_registration_path(ref: "1001", from: "stores_lp")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp")
    assert_select "a[href=?]", stores_lp_path, text: "戻る"
  end

  test "new registration keeps back link for store LP 202607" do
    get stores_new_registration_path(ref: "1001", from: "stores_lp_202607")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_path, text: "戻る"
  end

  test "new registration keeps utm params in form action" do
    get stores_new_registration_path(
      ref: "1001",
      from: "stores_lp_202607",
      utm_source: " meta ",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607",
      utm_content: "flyer_a"
    )

    assert_response :success
    assert_select "form[action=?]",
      stores_registrations_path(
        from: "stores_lp_202607",
        utm_source: "meta",
        utm_medium: "paid_social",
        utm_campaign: "store_recruit_202607",
        utm_content: "flyer_a"
      )
  end

  test "new registration falls back to current store LP when from is invalid" do
    get stores_new_registration_path(ref: "1001", from: "https://example.com")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path
    assert_select "a[href=?]", stores_lp_path, text: "戻る"
    assert_no_match "https://example.com", response.body
  end

  test "validation errors keep store LP 202607 back link" do
    assert_no_difference -> { Store.count } do
      post stores_registrations_path(from: "stores_lp_202607"), params: {
        store_registration: {
          store_name: "",
          email: "",
          password: "",
          password_confirmation: "",
          referral_code: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_path, text: "戻る"
  end

  test "validation errors keep ref and utm params" do
    referral_code = create_referral_code!("STORE-REG-RETURN-ERROR")

    assert_no_difference -> { Store.count } do
      post stores_registrations_path(
        from: "stores_lp_202607",
        utm_source: "meta",
        utm_medium: "paid_social",
        utm_campaign: "store_recruit_202607"
      ), params: {
        store_registration: valid_registration_params(
          store_name: "",
          referral_code: referral_code.code
        )
      }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]",
      stores_registrations_path(
        from: "stores_lp_202607",
        utm_source: "meta",
        utm_medium: "paid_social",
        utm_campaign: "store_recruit_202607"
      )
    assert_select "input[name='store_registration[referral_code]'][value=?]", referral_code.code
  end

  test "successful registration redirects to thanks and keeps existing admin edit destination" do
    referral_code = create_referral_code!("STORE-REG-RETURN-OK")

    assert_difference -> { Store.count }, +1 do
      assert_difference -> { User.count }, +1 do
        assert_difference -> { StoreMembership.count }, +1 do
          post stores_registrations_path(
            from: "stores_lp_202607",
            utm_source: "meta",
            utm_medium: "paid_social",
            utm_campaign: "store_recruit_202607"
          ), params: {
            store_registration: valid_registration_params(referral_code: referral_code.code)
          }
        end
      end
    end

    store = Store.order(:id).last
    thanks_path = URI(response.location).request_uri

    assert_redirected_to stores_registration_thanks_path(
      from: "stores_lp_202607",
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607"
    )
    assert_no_match(/ref=/, response.location)
    assert_equal referral_code, store.referral_code
    assert_equal store.id, @request.session[:current_store_id].to_i

    follow_redirect!

    assert_response :success
    assert_select "h1", text: "店舗登録が完了しました"
    assert_select "a[href=?]", edit_admin_store_path(store), text: "管理画面へ進む"

    get edit_admin_store_path(store)
    assert_response :success

    get thanks_path
    assert_redirected_to edit_admin_store_path(store)
  end

  test "registration thanks requires login" do
    get stores_registration_thanks_path

    assert_redirected_to new_user_session_path
  end

  test "logged in user without completion session is redirected to current store edit" do
    store = Store.create!(name: "No Completion Store")
    user = User.create!(email: "no-completion-store-admin@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: user, membership_role: :admin)
    sign_in user, scope: :user
    post admin_current_store_path, params: { store_id: store.id }

    get stores_registration_thanks_path

    assert_redirected_to edit_admin_store_path(store)
  end

  test "registration thanks rejects completion when current store no longer matches" do
    referral_code = create_referral_code!("STORE-REG-RETURN-MISMATCH")

    post stores_registrations_path, params: {
      store_registration: valid_registration_params(
        email: "store-registration-mismatch@example.com",
        referral_code: referral_code.code
      )
    }
    thanks_path = URI(response.location).request_uri

    registered_user = User.find_by!(email: "store-registration-mismatch@example.com")
    other_store = Store.create!(name: "Other Current Store")
    StoreMembership.create!(store: other_store, user: registered_user, membership_role: :admin)

    post admin_current_store_path, params: { store_id: other_store.id }
    get thanks_path

    assert_redirected_to edit_admin_store_path(other_store)
  end

  private

  def create_referral_code!(code)
    ReferralCode.create!(
      code: code,
      enabled: true,
      expires_at: 1.day.from_now
    )
  end

  def valid_registration_params(overrides = {})
    {
      store_name: "登録テスト店舗",
      email: "store-registration-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password",
      referral_code: "STORE-REG-RETURN"
    }.merge(overrides)
  end
end
