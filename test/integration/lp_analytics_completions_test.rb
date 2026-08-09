# frozen_string_literal: true

require "test_helper"

class LpAnalyticsCompletionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "JavaScriptに依存せずLP経由の正常店舗登録を匿名訪問へ記録する" do
    referral_code = create_referral_code!("LP-ANALYTICS-REGISTRATION")
    get stores_lp_202607_path, params: {
      utm_source: "meta",
      utm_campaign: "completion_test"
    }
    visit = LpAnalytics::Visit.order(:id).last

    assert_difference -> { Store.count }, 1 do
      assert_difference -> { completion_events("store_registration_complete").count }, 1 do
        post stores_registrations_path(from: "stores_lp_202607"), params: {
          store_registration: registration_params(referral_code: referral_code.code)
        }
      end
    end

    store = Store.order(:id).last
    event = completion_events("store_registration_complete").last
    assert_redirected_to stores_registration_thanks_path(from: "stores_lp_202607")
    assert_equal visit, store.lp_analytics_visit
    assert_equal visit, event.visit
    assert_equal store, event.completion_record
    assert_nil event.event_value
    assert_nil event.browser_event_id
    assert_equal({}, event.metadata)
  end

  test "店舗登録validation errorでは完了を記録しない" do
    get stores_lp_202607_path

    assert_no_difference -> { completion_events("store_registration_complete").count } do
      post stores_registrations_path(from: "stores_lp_202607"), params: {
        store_registration: registration_params(store_name: "", referral_code: "")
      }
    end

    assert_response :unprocessable_entity
  end

  test "改ざんされた訪問IDを店舗登録へ紐付けない" do
    referral_code = create_referral_code!("LP-ANALYTICS-TAMPERED-REGISTRATION")
    get stores_lp_202607_path

    assert_no_difference -> { completion_events("store_registration_complete").count } do
      post stores_registrations_path(from: "stores_lp_202607"), params: {
        lp_analytics_visit_id: SecureRandom.uuid,
        store_registration: registration_params(referral_code: referral_code.code)
      }
    end

    assert_redirected_to stores_registration_thanks_path(from: "stores_lp_202607")
    assert_nil Store.order(:id).last.lp_analytics_visit
  end

  test "LPを経由しない通常店舗登録では匿名訪問を作らない" do
    referral_code = create_referral_code!("LP-ANALYTICS-DIRECT-REGISTRATION")

    assert_no_difference [
      -> { LpAnalytics::Visit.count },
      -> { completion_events("store_registration_complete").count }
    ] do
      post stores_registrations_path, params: {
        store_registration: registration_params(referral_code: referral_code.code)
      }
    end

    assert_redirected_to stores_registration_thanks_path
    assert_nil Store.order(:id).last.lp_analytics_visit
  end

  test "JavaScriptに依存せずLP経由の正常問い合わせを匿名訪問へ記録する" do
    get stores_lp_202607_path, params: {
      utm_source: "meta",
      utm_campaign: "contact_completion_test"
    }
    visit = LpAnalytics::Visit.order(:id).last

    assert_difference -> { StoreContactSubmission.count }, 1 do
      assert_difference -> { completion_events("store_contact_complete").count }, 1 do
        post stores_contact_path(from: "stores_lp_202607"), params: contact_params
      end
    end

    submission = StoreContactSubmission.order(:id).last
    event = completion_events("store_contact_complete").last
    assert_redirected_to stores_contact_thanks_path(from: "stores_lp_202607")
    assert_equal visit, submission.lp_analytics_visit
    assert_equal visit, event.visit
    assert_equal submission, event.completion_record
    assert_equal({}, event.metadata)
  end

  test "問い合わせvalidation errorでは完了を記録しない" do
    get stores_lp_202607_path

    assert_no_difference -> { completion_events("store_contact_complete").count } do
      post stores_contact_path(from: "stores_lp_202607"), params: contact_params(name: "")
    end

    assert_response :unprocessable_entity
  end

  test "改ざんされた訪問IDを問い合わせへ紐付けない" do
    get stores_lp_202607_path

    assert_no_difference -> { completion_events("store_contact_complete").count } do
      post stores_contact_path(from: "stores_lp_202607"), params: contact_params.merge(
        lp_analytics_visit_id: SecureRandom.uuid
      )
    end

    assert_redirected_to stores_contact_thanks_path(from: "stores_lp_202607")
    assert_nil StoreContactSubmission.order(:id).last.lp_analytics_visit
  end

  test "複数tabではhidden訪問IDが示す許可済み訪問へ問い合わせを紐付ける" do
    get stores_lp_202607_path, params: { utm_content: "first_tab" }
    first_visit = LpAnalytics::Visit.order(:id).last
    get stores_lp_202607_path, params: { utm_content: "second_tab" }
    second_visit = LpAnalytics::Visit.order(:id).last

    post stores_contact_path(from: "stores_lp_202607"), params: contact_params.merge(
      lp_analytics_visit_id: first_visit.public_id
    )

    submission = StoreContactSubmission.order(:id).last
    assert_redirected_to stores_contact_thanks_path(from: "stores_lp_202607")
    assert_equal first_visit, submission.lp_analytics_visit
    refute_equal second_visit, submission.lp_analytics_visit
    assert_equal first_visit, completion_events("store_contact_complete").last.visit
  end

  test "LPを経由しない通常問い合わせでは匿名訪問を作らない" do
    assert_no_difference [
      -> { LpAnalytics::Visit.count },
      -> { completion_events("store_contact_complete").count }
    ] do
      post stores_contact_path, params: contact_params
    end

    assert_redirected_to stores_contact_thanks_path
    assert_nil StoreContactSubmission.order(:id).last.lp_analytics_visit
  end

  private

  def completion_events(event_type)
    LpAnalytics::Event.where(event_type: event_type)
  end

  def create_referral_code!(code)
    ReferralCode.create!(code: code, enabled: true, expires_at: 1.day.from_now)
  end

  def registration_params(overrides = {})
    {
      store_name: "LP行動分析登録店舗",
      email: "lp-analytics-registration-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password",
      referral_code: ""
    }.merge(overrides)
  end

  def contact_params(overrides = {})
    {
      store_contact_submission: {
        name: "Owner Name",
        store_name: "Sample Store",
        business_type: "Girls Bar",
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00"
      }.merge(overrides)
    }
  end
end
