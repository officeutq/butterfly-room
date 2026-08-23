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

  test "202609 LPを別訪問として作成し安定したsection・CTAの計測keyを出力する" do
    get stores_lp_202607_path, params: { utm_content: "old_lp" }
    old_visit = LpAnalytics::Visit.order(:id).last

    assert_difference "LpAnalytics::Visit.count", 1 do
      get stores_lp_202609_path, params: {
        from: "meta",
        utm_source: "facebook",
        utm_campaign: "campaign_202609",
        utm_content: "new_lp"
      }
    end

    assert_response :success
    visit = LpAnalytics::Visit.order(:id).last
    assert_equal LpAnalytics::Configuration::STORE_LP_202607, old_visit.lp_identifier
    assert_equal LpAnalytics::Configuration::STORE_LP_202609, visit.lp_identifier
    assert_not_equal old_visit.public_id, visit.public_id
    assert_equal "smartphone", visit.device_type if request.user_agent.to_s.include?("Mobile")
    assert_select(
      ".store-lp-202609[data-controller~='store-lp-202609']" \
      "[data-store-lp-202609-events-url-value=?]" \
      "[data-store-lp-202609-visit-id-value=?]",
      lp_analytics_events_path,
      visit.public_id
    )

    section_values = css_select(
      '[data-lp-analytics-reach-type="section_reached"]'
    ).map { |node| node["data-lp-analytics-event-value"] }
    assert_equal %w[
      existing_customer_opportunity
      service_introduction
      usage_mechanism
      service_comparison
      adoption_cost
      usage_scenes
      getting_started
      final_opportunity_cta
    ], section_values

    cta_reach_values = css_select(
      '[data-lp-analytics-reach-type="cta_reached"]'
    ).map { |node| node["data-lp-analytics-event-value"] }
    cta_click_values = css_select(
      "[data-lp-analytics-click-value]"
    ).map { |node| node["data-lp-analytics-click-value"] }
    expected_ctas = %w[
      header_registration
      hero_registration
      hero_contact
      hero_faq
      bottom_registration
      bottom_contact
      bottom_faq
      mobile_registration
    ]
    assert_equal expected_ctas, cta_reach_values
    assert_equal expected_ctas, cta_click_values
    assert_select "[data-lp-analytics-faq-value]", count: 0
  end

  test "202607 LPから遷移した店舗登録formに表示計測を設定する" do
    get stores_lp_202607_path
    get stores_new_registration_path(from: "stores_lp_202607")

    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-events-url-value=?]" \
      "[data-lp-analytics-form-event-type-value=?]" \
      "[data-lp-analytics-form-lp-identifier-value=?]",
      lp_analytics_events_path,
      "store_registration_form_view",
      LpAnalytics::Configuration::STORE_LP_202607
    )
  end

  test "202607 LPから遷移したお問い合わせformに表示計測を設定する" do
    get stores_lp_202607_path
    get stores_contact_path(from: "stores_lp_202607")

    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-events-url-value=?]" \
      "[data-lp-analytics-form-event-type-value=?]" \
      "[data-lp-analytics-form-lp-identifier-value=?]",
      lp_analytics_events_path,
      "store_contact_form_view",
      LpAnalytics::Configuration::STORE_LP_202607
    )
  end

  test "202609 LPから遷移した登録・お問い合わせformに表示計測を設定する" do
    get stores_lp_202609_path

    get stores_new_registration_path(from: "stores_lp_202609")
    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-event-type-value=?]" \
      "[data-lp-analytics-form-lp-identifier-value=?]",
      "store_registration_form_view",
      LpAnalytics::Configuration::STORE_LP_202609
    )

    get stores_contact_path(from: "stores_lp_202609")
    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-event-type-value=?]" \
      "[data-lp-analytics-form-lp-identifier-value=?]",
      "store_contact_form_view",
      LpAnalytics::Configuration::STORE_LP_202609
    )
  end

  test "別LPの訪問sessionだけでは202609 formの表示計測を設定しない" do
    get stores_lp_202607_path
    get stores_new_registration_path(from: "stores_lp_202609")

    assert_response :success
    assert_select "[data-controller~='lp-analytics-form']", count: 0
  end

  test "複数tab相当で現在のsessionが別LPでも許可済みの遷移元LPをformへ設定する" do
    get stores_lp_202607_path, params: { utm_content: "first_tab" }
    get stores_lp_202609_path, params: { utm_content: "second_tab" }
    get stores_new_registration_path(from: "stores_lp_202607")

    assert_response :success
    assert_select(
      "form[data-controller~='lp-analytics-form']" \
      "[data-lp-analytics-form-lp-identifier-value=?]",
      LpAnalytics::Configuration::STORE_LP_202607
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
