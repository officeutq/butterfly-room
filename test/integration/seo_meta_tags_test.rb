# frozen_string_literal: true

require "test_helper"

class SeoMetaTagsTest < ActionDispatch::IntegrationTest
  ROOT_DESCRIPTION =
    "Butterflyve（バタフライブ）は、視聴者・キャスト・店舗をつなぐライブ配信サービスです。配信を見て、コメントし、ドリンクで応援できます。"
  STORE_LP_DESCRIPTION =
    "Butterflyve（バタフライブ）は、夜の店が既存客向けにライブ配信を行い、ドリンク送信と消化で売上をつくる店舗向けサービスです。"

  test "guest root exposes brand h1 and SEO metadata" do
    get root_path

    assert_response :success

    doc = Nokogiri::HTML(@response.body)

    assert_equal 1, doc.css("h1").size
    assert_includes doc.at_css("h1").text, "Butterflyve（バタフライブ）"
    assert_equal "夜を、ライブ体験に。 | Butterflyve（バタフライブ）", doc.at_css("title").text
    assert_equal ROOT_DESCRIPTION, doc.at_css("meta[name='description']")["content"]
    assert_equal "Butterflyve（バタフライブ）", doc.at_css("meta[property='og:site_name']")["content"]
    assert_equal "Butterflyve（バタフライブ）", doc.at_css("meta[name='application-name']")["content"]
    assert_nil doc.at_css("meta[name='robots']")

    structured_data = JSON.parse(doc.at_css("script[type='application/ld+json']").text)
    assert_equal "https://schema.org", structured_data["@context"]
    assert_equal "WebSite", structured_data["@type"]
    assert_equal "Butterflyve", structured_data["name"]
    assert_equal "バタフライブ", structured_data["alternateName"]
    assert_equal "https://butterflyve.jp/", structured_data["url"]
  end

  test "store LP exposes individual SEO metadata without ref in canonical URL" do
    get stores_lp_path(ref: "abc123")

    assert_response :success

    doc = Nokogiri::HTML(@response.body)

    assert_equal 1, doc.css("h1").size
    assert_includes doc.at_css("h1").text, "Butterflyve（バタフライブ）"
    assert_equal "店舗向けライブ配信LP | Butterflyve（バタフライブ）", doc.at_css("title").text
    assert_equal STORE_LP_DESCRIPTION, doc.at_css("meta[name='description']")["content"]
    assert_equal "Butterflyve（バタフライブ）", doc.at_css("meta[property='og:site_name']")["content"]
    assert_equal "店舗向けライブ配信LP | Butterflyve（バタフライブ）", doc.at_css("meta[property='og:title']")["content"]
    assert_equal STORE_LP_DESCRIPTION, doc.at_css("meta[property='og:description']")["content"]
    assert_equal stores_lp_url, doc.at_css("link[rel='canonical']")["href"]
    assert_equal stores_lp_url, doc.at_css("meta[property='og:url']")["content"]
    assert_match %r{\Ahttps?://}, doc.at_css("meta[property='og:image']")["content"]
    assert_nil doc.at_css("meta[name='robots']")
    assert_nil doc.at_css("script[type='application/ld+json']")
    assert_select "a", text: "無料で店舗登録する",
      href: stores_new_registration_path(ref: "abc123", from: "stores_lp")
  end

  test "store LP 202607 is noindex while it is a confirmation page" do
    get stores_lp_202607_path

    assert_response :success

    doc = Nokogiri::HTML(@response.body)

    assert_equal "夜のお店のための新しい遠隔配信ツール | Butterflyve（バタフライブ）", doc.at_css("title").text
    assert_equal stores_lp_202607_url, doc.at_css("link[rel='canonical']")["href"]
    assert_equal stores_lp_202607_url, doc.at_css("meta[property='og:url']")["content"]
    assert_includes doc.at_css("meta[name='robots']")["content"], "noindex"
    assert_select ".store-lp-202607"
    assert_select "a[href=?]", stores_new_registration_path(from: "stores_lp_202607"), minimum: 1
  end

  test "staging forces noindex and nofollow on a public page" do
    Staging::Runtime.stub(:staging?, true) do
      Staging::Runtime.stub(:enabled?, false) do
        get stores_lp_path
      end
    end

    assert_response :success
    robots = Nokogiri::HTML(response.body).at_css("meta[name='robots']")["content"]
    assert_includes robots, "noindex"
    assert_includes robots, "nofollow"
  end
end
