# frozen_string_literal: true

require "test_helper"

class GtmPagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  GTM_ID = ApplicationController::GTM_CONTAINER_ID

  setup do
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "gtm is output once on public marketing pages" do
    get stores_lp_path
    assert_response :success
    assert_gtm_once

    get stores_lp_202607_path
    assert_response :success
    assert_gtm_once

    get stores_contact_path
    assert_response :success
    assert_gtm_once

    get stores_new_registration_path(ref: "1001")
    assert_response :success
    assert_gtm_once
  end

  test "gtm is output once on contact thanks page" do
    post stores_contact_path, params: submission_params
    follow_redirect!

    assert_response :success
    assert_gtm_once
  end

  test "gtm is output once on registration thanks page" do
    referral_code = create_referral_code!("GTM-STORE-REG")

    post stores_registrations_path, params: {
      store_registration: registration_params(referral_code: referral_code.code)
    }
    follow_redirect!

    assert_response :success
    assert_gtm_once
  end

  test "gtm remains on validation error pages rendered from create" do
    post stores_contact_path, params: submission_params(name: "")

    assert_response :unprocessable_entity
    assert_gtm_once

    post stores_registrations_path, params: {
      store_registration: registration_params(store_name: "", referral_code: "")
    }

    assert_response :unprocessable_entity
    assert_gtm_once
  end

  test "gtm is not output on unrelated pages or admin pages" do
    get root_path
    assert_response :success
    assert_no_gtm

    store = Store.create!(name: "GTM Admin Store")
    admin = User.create!(email: "gtm-admin@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: admin, membership_role: :admin)
    sign_in admin, scope: :user

    get edit_admin_store_path(store)

    assert_response :success
    assert_no_gtm
  end

  test "staging disables GTM scripts and conversion events" do
    with_env("APP_ENV" => "staging", "BASIC_AUTH_ENABLED" => "false", "GTM_ENABLED" => nil) do
      get stores_lp_path
      assert_response :success
      assert_no_gtm

      post stores_contact_path, params: submission_params
      follow_redirect!
      assert_response :success
      assert_no_gtm
      assert_no_match(/window\.dataLayer\.push/, response.body)
    end
  end

  private

  def assert_gtm_once
    assert_equal 1, response.body.scan("googletagmanager.com/gtm.js").size
    assert_equal 1, response.body.scan("googletagmanager.com/ns.html?id=#{GTM_ID}").size
  end

  def assert_no_gtm
    assert_no_match(/googletagmanager\.com\/gtm\.js/, response.body)
    assert_no_match(/googletagmanager\.com\/ns\.html/, response.body)
  end

  def create_referral_code!(code)
    ReferralCode.create!(
      code: code,
      enabled: true,
      expires_at: 1.day.from_now
    )
  end

  def submission_params(overrides = {})
    {
      store_contact_submission: {
        name: "Owner Name",
        store_name: "Sample Store",
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00"
      }.merge(overrides)
    }
  end

  def registration_params(overrides = {})
    {
      store_name: "GTM登録店舗",
      email: "gtm-store-registration-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password",
      referral_code: "GTM-STORE-REG"
    }.merge(overrides)
  end
end
