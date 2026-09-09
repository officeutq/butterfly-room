# frozen_string_literal: true

require "test_helper"

class AdminProxyStoreRegistrationTest < ActionDispatch::IntegrationTest
  setup do
    @referral_code = ReferralCode.create!(code: "PROXY-INTEGRATION", enabled: true, expires_at: 1.day.from_now)
    @actor = User.create!(email: "proxy-integration@example.com", password: "password", role: :store_admin)
    @management_store = Store.create!(
      name: "Proxy Management Store",
      published: false,
      sales_support_company: true
    )
    StoreMembership.create!(store: @management_store, user: @actor, membership_role: :admin)
  end

  test "sales support company admin with one store can reach proxy store creation from the dashboard" do
    sign_in @actor, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", new_admin_store_path, text: /代行対象店舗を作成/

    get new_admin_store_path
    assert_response :success
  end

  test "dashboard hides proxy store creation after the support company flag is disabled" do
    @management_store.update!(sales_support_company: false)
    sign_in @actor, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", new_admin_store_path, count: 0
  end

  test "sales support company admin can create and switch to a regular proxy store" do
    sign_in @actor, scope: :user

    get new_admin_store_path
    assert_response :success

    assert_no_difference "User.count" do
      post admin_stores_path, params: {
        proxy_store_registration: {
          store_name: "Created Proxy Store",
          referral_code: @referral_code.code
        }
      }
    end

    store = Store.find_by!(name: "Created Proxy Store")
    assert_redirected_to edit_admin_store_path(store)
    assert_equal store.id, session[:current_store_id].to_i
    assert_nil session[:current_booth_id]
    assert_not store.sales_support_company?
    assert StoreMembership.admin_only.exists?(store: store, user: @actor)
    follow_redirect!
    assert_select "form[data-controller~='store-ai-autofill'][data-image-pair-form-always-submit-value='true']"
    assert_select "form[data-store-ai-autofill-image-url-value=?]", image_admin_store_ai_autofill_path(store)
    assert_select "[data-store-ai-autofill-target='modal']", count: 0
    assert_nil session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]

    token = Stores::AiAutofill::ImageSources.verifier.generate(
      { "store_id" => store.id, "user_id" => @actor.id, "sources" => [] },
      purpose: Stores::AiAutofill::ImageSources::PURPOSE, expires_in: 5.minutes
    )
    post image_admin_store_ai_autofill_path(store), params: { image_token: token }, as: :json
    assert_response :no_content
  end

  test "regular store admins and system_admin are forbidden" do
    @management_store.update!(sales_support_company: false)
    sign_in @actor, scope: :user
    get new_admin_store_path
    assert_response :forbidden

    system_admin = User.create!(email: "proxy-system@example.com", password: "password", role: :system_admin)
    sign_in system_admin, scope: :user
    get new_admin_store_path
    assert_response :forbidden
  end

  test "guest keeps the existing login redirect" do
    get new_admin_store_path
    assert_redirected_to new_user_session_path
  end
end
