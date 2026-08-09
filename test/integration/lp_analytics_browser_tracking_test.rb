# frozen_string_literal: true

require "test_helper"

class LpAnalyticsBrowserTrackingTest < ActionDispatch::IntegrationTest
  test "202607 LPに安定したsection・CTA・FAQの計測keyを出力する" do
    get stores_lp_202607_path, params: {
      from: "meta",
      utm_source: "facebook",
      utm_campaign: "campaign_a"
    }

    assert_response :success
    visit = LpAnalytics::Visit.order(:id).last
    assert_select(
      ".store-lp-202607[data-controller~='store-lp-202607']" \
      "[data-store-lp-202607-events-url-value=?]" \
      "[data-store-lp-202607-visit-id-value=?]",
      lp_analytics_events_path,
      visit.public_id
    )

    section_values = css_select(
      '[data-lp-analytics-reach-type="section_reached"]'
    ).map { |node| node["data-lp-analytics-event-value"] }
    assert_equal %w[USAGE STRENGTHS SYSTEM PRICING FLOW CAST QA bottom_cta], section_values

    cta_reach_values = css_select(
      '[data-lp-analytics-reach-type="cta_reached"]'
    ).map { |node| node["data-lp-analytics-event-value"] }
    cta_click_values = css_select(
      "[data-lp-analytics-click-value]"
    ).map { |node| node["data-lp-analytics-click-value"] }
    expected_ctas = %w[
      pc_sidebar_registration
      hero_registration
      flow_registration
      bottom_contact
      bottom_registration
    ]
    assert_equal expected_ctas, cta_reach_values
    assert_equal expected_ctas, cta_click_values

    faq_values = css_select("[data-lp-analytics-faq-value]").map do |node|
      node["data-lp-analytics-faq-value"]
    end
    assert_equal %w[faq_1 faq_2 faq_3 faq_4], faq_values
  end

  test "202607 LPから遷移した店舗登録formに表示計測を設定する" do
    get stores_lp_202607_path
    get stores_new_registration_path(from: "stores_lp_202607")

    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-events-url-value=?]" \
      "[data-lp-analytics-form-event-type-value=?]",
      lp_analytics_events_path,
      "store_registration_form_view"
    )
  end

  test "202607 LPから遷移したお問い合わせformに表示計測を設定する" do
    get stores_lp_202607_path
    get stores_contact_path(from: "stores_lp_202607")

    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-events-url-value=?]" \
      "[data-lp-analytics-form-event-type-value=?]",
      lp_analytics_events_path,
      "store_contact_form_view"
    )
  end

  test "LPを経由していないformではLP訪問の表示計測を設定しない" do
    get stores_new_registration_path(from: "stores_lp_202607")

    assert_response :success
    assert_select "[data-controller~='lp-analytics-form']", count: 0

    get stores_contact_path(from: "stores_lp_202607")

    assert_response :success
    assert_select "[data-controller~='lp-analytics-form']", count: 0
  end

  test "通常LP向けformには202607版の表示計測を設定しない" do
    get stores_lp_202607_path
    get stores_new_registration_path(from: "stores_lp")

    assert_response :success
    assert_select "[data-controller~='lp-analytics-form']", count: 0

    get stores_contact_path(from: "stores_lp")

    assert_response :success
    assert_select "[data-controller~='lp-analytics-form']", count: 0
  end
end
