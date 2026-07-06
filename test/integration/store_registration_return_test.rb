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
end
