# frozen_string_literal: true

require "test_helper"

class StoreLp202609Test < ActionDispatch::IntegrationTest
  test "guest can view the 202609 store LP with finalized copy and CTA links" do
    get stores_lp_202609_path

    assert_response :success
    assert_select ".store-lp-202609[data-controller='store-lp-202609']"
    assert_select "h1", count: 1, text: /営業時間外に売上が止まるのは、.*本当に当たり前でしょうか？/
    assert_includes response.body, "夜のお店のためにつくられたライブ配信サービス"
    assert_includes response.body, "配信終了時に未消化だったギフトはお客様へ返却され"
    assert_includes response.body, "アカウント作成・ログインが必要です"
    assert_includes response.body, "そのキャスト専用のブースが自動で作成されます"

    assert_select "a[href=?]", stores_new_registration_path(from: "stores_lp_202609"), minimum: 3
    assert_select "a[href=?]", stores_contact_path(from: "stores_lp_202609"), minimum: 2
    assert_select "a[href=?]", "/stores/faq?return_to=%2Fstores%2Flp_202609", minimum: 2

    assert_select "img[src*='store_lp_202609/hero_cast_customer_connection']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_before_open']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_day_off']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_remote_customer']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_sns_connection']", count: 1
    assert_select "link[rel='stylesheet'][href*='store_lp_202609']", count: 1
  end

  test "202609 store LP is noindex and exposes its own canonical metadata" do
    get stores_lp_202609_path(ref: "abc123")

    assert_response :success
    doc = Nokogiri::HTML(response.body)

    assert_equal "来店できない時間を店舗売上の機会に | Butterflyve（バタフライブ）", doc.at_css("title").text
    assert_equal stores_lp_202609_url, doc.at_css("link[rel='canonical']")["href"]
    assert_equal stores_lp_202609_url, doc.at_css("meta[property='og:url']")["content"]
    assert_includes doc.at_css("meta[name='robots']")["content"], "noindex"
  end

  test "202609 store LP stores sanitized attribution and keeps tracking out of CTA URLs" do
    get stores_lp_202609_path, params: {
      ref: "  partner-202609  ",
      utm_source: " meta ",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202609",
      utm_content: "creative_a"
    }

    assert_response :success
    assert_equal(
      {
        "from" => "stores_lp_202609",
        "utm_source" => "meta",
        "utm_medium" => "paid_social",
        "utm_campaign" => "store_recruit_202609",
        "utm_content" => "creative_a"
      },
      @request.session[ApplicationController::STORE_LP_202609_ATTRIBUTION_SESSION_KEY]
    )
    assert_equal "partner-202609", @request.session[ApplicationController::STORE_LP_202609_REF_SESSION_KEY]
    assert_select "a[href=?]",
                  stores_new_registration_path(from: "stores_lp_202609", ref: "partner-202609"),
                  minimum: 3
    assert_select "a[href=?]", stores_contact_path(from: "stores_lp_202609"), minimum: 2
    assert_no_match(/stores\/new_registration[^\"]*utm_source/, response.body)
    assert_no_match(/stores\/contact[^\"]*utm_source/, response.body)

    faq_link = Nokogiri::HTML(response.body).css("a").find do |link|
      link.text.strip == "店舗向けFAQを見る"
    end
    faq_href = faq_link["href"]
    faq_uri = URI.parse(faq_href)
    faq_query = Rack::Utils.parse_query(faq_uri.query)
    return_uri = URI.parse(faq_query.fetch("return_to"))
    return_query = Rack::Utils.parse_query(return_uri.query)

    assert_equal "/stores/lp_202609", return_uri.path
    assert_equal "partner-202609", return_query["ref"]
    assert_equal "meta", return_query["utm_source"]
    assert_equal "paid_social", return_query["utm_medium"]
    assert_equal "store_recruit_202609", return_query["utm_campaign"]
    assert_equal "creative_a", return_query["utm_content"]
  end

  test "202609 form pages return through the dedicated return route" do
    get stores_contact_path(from: "stores_lp_202609")

    assert_response :success
    assert_select "form[action=?]", stores_contact_path(from: "stores_lp_202609")
    assert_select "a[href=?][data-turbo-prefetch='false'][data-turbo='false']",
                  stores_lp_202609_return_path,
                  minimum: 1

    get stores_new_registration_path(from: "stores_lp_202609", ref: "partner-202609")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp_202609")
    assert_select "input[name='store_registration[referral_code]'][value='partner-202609']"
    assert_select "a[href=?][data-turbo-prefetch='false'][data-turbo='false']",
                  stores_lp_202609_return_path,
                  minimum: 1
  end

  test "202609 internal return preserves attribution and referral once" do
    get stores_lp_202609_path, params: {
      ref: "partner-202609",
      utm_source: "meta",
      utm_medium: "paid_social"
    }

    get stores_lp_202609_return_path

    assert_redirected_to stores_lp_202609_path(ref: "partner-202609")
    assert_equal true,
                 @request.session[ApplicationController::PRESERVE_STORE_LP_202609_ATTRIBUTION_ONCE_SESSION_KEY]

    follow_redirect!

    assert_response :success
    assert_nil @request.session[ApplicationController::PRESERVE_STORE_LP_202609_ATTRIBUTION_ONCE_SESSION_KEY]
    assert_equal "meta",
                 @request.session[ApplicationController::STORE_LP_202609_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "partner-202609",
                 @request.session[ApplicationController::STORE_LP_202609_REF_SESSION_KEY]
  end

  test "202609 attribution does not overwrite 202607 attribution" do
    get stores_lp_202607_path, params: { ref: "old", utm_source: "meta-old" }
    get stores_lp_202609_path, params: { ref: "new", utm_source: "meta-new" }

    assert_equal "meta-old",
                 @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "old", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
    assert_equal "meta-new",
                 @request.session[ApplicationController::STORE_LP_202609_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "new", @request.session[ApplicationController::STORE_LP_202609_REF_SESSION_KEY]
  end
end
