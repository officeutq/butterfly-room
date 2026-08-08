# frozen_string_literal: true

require "test_helper"

class SalesSupportCompanyProxyFlowTest < ActionDispatch::IntegrationTest
  test "proxy authority follows support company memberships through store and manager registration" do
    ActionMailer::Base.deliveries.clear
    referral_code = ReferralCode.create!(
      code: "SUPPORT-FLOW",
      enabled: true,
      expires_at: 1.day.from_now
    )
    company_a = Store.create!(name: "営業支援会社A", sales_support_company: true)
    yamada = User.create!(email: "yamada@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: company_a, user: yamada, membership_role: :admin)

    sign_in yamada, scope: :user

    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", new_admin_store_path, text: /代行対象店舗を作成/

    post admin_stores_path, params: {
      proxy_store_registration: {
        store_name: "店舗B",
        referral_code: referral_code.code
      }
    }

    store_b = Store.find_by!(name: "店舗B")
    assert_not store_b.sales_support_company?
    assert StoreMembership.admin_only.exists?(store: store_b, user: yamada)
    assert_equal store_b.id, session[:current_store_id].to_i

    get admin_store_admin_invitations_path
    assert_response :success
    assert_select "a[href=?]", new_admin_store_admin_proxy_registration_path,
                  text: "店舗責任者を登録（代行用）"

    post admin_store_admin_proxy_registration_path, params: {
      store_admin_proxy_registration: {
        display_name: "B店長",
        email: "store-b-manager@example.com"
      }
    }

    manager = User.find_by!(email: "store-b-manager@example.com")
    assert_redirected_to admin_store_admin_invitations_path
    assert StoreMembership.admin_only.exists?(store: store_b, user: manager)
    assert_not manager.store_registration_proxy_allowed?

    company_a.update!(sales_support_company: false)
    assert_not yamada.store_registration_proxy_allowed?

    get dashboard_path
    assert_select "a[href=?]", new_admin_store_path, count: 0

    get new_admin_store_admin_proxy_registration_path
    assert_response :forbidden

    company_c = Store.create!(name: "営業支援会社C", sales_support_company: true)
    StoreMembership.create!(store: company_c, user: yamada, membership_role: :admin)

    assert yamada.store_registration_proxy_allowed?
    get dashboard_path
    assert_select "a[href=?]", new_admin_store_path, text: /代行対象店舗を作成/
  end
end
