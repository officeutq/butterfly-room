# frozen_string_literal: true

require "test_helper"

class StoreLp202609Test < ActionDispatch::IntegrationTest
  test "adding the 202609 layout leaves the existing 202607 layout unchanged" do
    get stores_lp_202607_path

    assert_response :success
    assert_select "link[rel='stylesheet'][href*='store_lp_202607']", count: 1
    assert_select "link[rel='stylesheet'][href*='application']", count: 0
  end

  test "guest can view the 202609 store LP with finalized copy and CTA links" do
    get stores_lp_202609_path

    assert_response :success
    assert_select ".store-lp-202609[data-controller='store-lp-202609']"
    assert_select ".lp-eyebrow", count: 1, text: /FOR NIGHT STORES.*お店とキャストとお客様をつなぐ/
    assert_select "h1", count: 1, text: /来店がなければ、.*売上もない。.*それ、当たり前ですか？/
    assert_includes response.body, "夜のお店のためにつくられたライブ配信サービス"
    assert_includes response.body, "配信終了時に未消化だったギフトはお客様へ返却され"
    assert_includes response.body, "アカウント作成・ログインが必要です"
    assert_includes response.body, "そのキャスト専用のブースが自動で作成されます"
    assert_includes response.body, "飲みに出られない"
    assert_includes response.body, "会いたいけれどお店には行けない"
    assert_includes response.body, "投資は必要ありません"
    assert_includes response.body, "オンラインでもつながる。"
    assert_includes response.body, "「売り上げになる」"
    assert_includes response.body, "夜のお店での利用を想定しています。"
    assert_select ".lp-service__choice", count: 1, text: "「オンライン」という新しい選択肢"
    assert_includes response.body, "「店舗を登録する」から始められます。"
    assert_includes response.body, "&copy; Office UTQ Inc."
    assert_not_includes response.body, "最初から夜のお店での利用を想定しています。"
    assert_select ".lp-step-card__icon, .lp-easy-card__mark, .lp-no-app__phone, .lp-start-card__icon", count: 0

    assert_select "a[href=?]", stores_new_registration_path(from: "stores_lp_202609"), minimum: 4
    assert_select "a[href=?]", stores_contact_path(from: "stores_lp_202609"), minimum: 4
    assert_select "a[href=?]",
                  stores_faq_path(return_to: stores_lp_202609_return_path),
                  minimum: 2
    assert_select ".lp-header__actions a", count: 2
    assert_select ".lp-mobile-cta a", count: 2

    assert_select "img[src*='store_lp_202609/hero_cast_customer_connection'][src$='.webp']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_before_open'][src$='.webp']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_day_off'][src$='.webp']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_remote_customer'][src$='.webp']", count: 1
    assert_select "img[src*='store_lp_202609/use_case_sns_connection'][src$='.webp']", count: 1
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
                  minimum: 4
    assert_select "a[href=?]", stores_contact_path(from: "stores_lp_202609"), minimum: 4
    assert_no_match(/stores\/new_registration[^\"]*utm_source/, response.body)
    assert_no_match(/stores\/contact[^\"]*utm_source/, response.body)

    faq_link = Nokogiri::HTML(response.body).css("a").find do |link|
      link.text.strip == "店舗向けFAQを見る"
    end
    faq_href = faq_link["href"]
    faq_uri = URI.parse(faq_href)
    faq_query = Rack::Utils.parse_query(faq_uri.query)
    assert_equal stores_lp_202609_return_path, faq_query.fetch("return_to")
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
