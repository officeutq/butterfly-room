# frozen_string_literal: true

require "test_helper"

class SystemAdminReferralCodesTest < ActionDispatch::IntegrationTest
  setup do
    @customer     = User.create!(email: "customer_rc@example.com", password: "password", role: :customer)
    @store_admin  = User.create!(email: "admin_rc@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_rc@example.com", password: "password", role: :system_admin)
  end

  test "non system_admin cannot access (403)" do
    sign_in @customer, scope: :user
    get system_admin_referral_codes_path
    assert_response :forbidden

    sign_in @store_admin, scope: :user
    get system_admin_referral_codes_path
    assert_response :forbidden
  end

  test "system_admin can list/create/update(toggle)" do
    sign_in @system_admin, scope: :user

    get system_admin_referral_codes_path
    assert_response :success

    # create
    post system_admin_referral_codes_path, params: {
      referral_code: {
        code: "TESTCODE",
        label: "label1",
        enabled: true
      }
    }
    assert_response :redirect
    assert_redirected_to system_admin_referral_codes_path

    rc = ReferralCode.find_by!(code: "TESTCODE")
    assert_equal true, rc.enabled?

    # toggle disable
    patch system_admin_referral_code_path(rc), params: { referral_code: { enabled: false } }
    assert_response :redirect
    assert_redirected_to system_admin_referral_codes_path
    assert_equal false, rc.reload.enabled?
  end
end
