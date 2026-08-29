# frozen_string_literal: true

require "test_helper"

class StoreFaqTest < ActionDispatch::IntegrationTest
  test "guest can read every canonical store FAQ without JavaScript" do
    get stores_faq_path

    assert_response :success
    assert_select ".store-faq[data-controller='store-faq']", count: 1
    assert_select ".store-faq__category", count: 10
    assert_select ".store-faq__category[hidden]", count: 0
    assert_select "a.store-faq__category-button[href^='#store-faq-category-']", count: 10
    assert_select ".store-faq__category-number", count: 10
    assert_select ".store-faq__question", count: 47
    assert_select "details.store-faq__question summary[data-action='click->store-faq#toggleQuestion']", count: 47
    assert_select ".store-faq__section-actions", count: 10
    assert_select "a.store-faq__section-action--top[href='#store-faq-top']", count: 10, text: /ページトップ/
    assert_select "a.store-faq__section-action--back", count: 10, text: /戻る/

    (1..47).each do |number|
      assert_select "#faq-q#{number}", count: 1
    end

    assert_select "a.store-faq__back-link[href=?]", stores_lp_path, count: 1, text: /戻る/
    assert_select "a[href=?]", stores_lp_path, minimum: 11
  end

  test "catalog keeps the canonical categories and continuous Q numbers" do
    assert_equal 10, StoreFaqCatalog.categories.size
    assert_equal (1..47).to_a, StoreFaqCatalog.questions.map { |faq| faq.fetch(:number) }
    assert_equal [
      "サービスについて",
      "料金・売上について",
      "利用開始について",
      "配信について",
      "ブースについて",
      "お客様の利用方法について",
      "店舗管理について",
      "店舗情報の公開について",
      "安全管理・サポートについて",
      "退会について"
    ], StoreFaqCatalog.categories.map { |category| category.fetch(:title) }
  end

  test "canonical implementation notes are rendered without rewording" do
    get stores_faq_path

    assert_response :success
    assert_includes response.body, "ダッシュボードの「振込先口座設定」から、振込先口座を登録・変更できます。"
    assert_includes response.body, "そのキャスト専用のブースが自動で作成されます。"
    assert_includes response.body, "配信を終了したうえでアーカイブされます。"
    assert_includes response.body, "「非公開」に設定した店舗と所属ブースは、一般ユーザー向け画面に表示されません。"
    assert_includes response.body, "未ログインで視聴しているお客様は視聴者数に含まれません。"
    assert_includes response.body, "アカウントを作成せずに公開中の配信を視聴できます。"
    assert_includes response.body, "コメントもリアルタイムで閲覧できます。"
    assert_includes response.body, "すべての機能を利用するには、お客様のアカウント作成とログインが必要です。"
    assert_not_includes response.body, "初回利用時にはお客様のアカウント作成が必要です。"
  end

  test "FAQ is accessible while signed in with every role" do
    %i[customer cast store_admin system_admin].each do |role|
      user = User.create!(
        email: "store-faq-#{role}@example.com",
        password: "password123",
        role:
      )

      sign_in user, scope: :user
      get stores_faq_path
      assert_response :success, "#{role} should be able to access the store FAQ"
      sign_out user
    end
  end

  test "return link accepts only the expected internal pages" do
    return_to = "/stores/lp_202609?utm_source=meta&utm_medium=paid_social&ref=partner"
    get stores_faq_path(return_to:)

    assert_response :success
    assert_select "a[href=?]", return_to, minimum: 2

    get stores_faq_path(return_to: stores_lp_202609_return_path)

    assert_response :success
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]",
                  stores_lp_202609_return_path,
                  "false",
                  "false",
                  minimum: 2

    [
      "https://example.com/steal",
      "//example.com/steal",
      "/stores/contact",
      "/stores/lp_202609\nLocation: https://example.com",
      "/stores/lp_202609%0ALocation:https://example.com"
    ].each do |invalid_return_to|
      get stores_faq_path(return_to: invalid_return_to)

      assert_response :success
      assert_select "a.store-faq__back-link[href=?]", stores_lp_path, count: 1
    end
  end

  test "LP pages link to the FAQ while 202607 remains unchanged" do
    get stores_lp_path(ref: "partner", utm_source: "meta")

    assert_response :success
    faq_link = Nokogiri::HTML(response.body).css("a").find { |link| link.text.strip == "店舗向けFAQ" }
    faq_query = Rack::Utils.parse_query(URI.parse(faq_link["href"]).query)
    return_uri = URI.parse(faq_query.fetch("return_to"))
    assert_equal "/stores/lp", return_uri.path
    assert_equal({ "ref" => "partner", "utm_source" => "meta" }, Rack::Utils.parse_query(return_uri.query))

    get stores_lp_202609_path
    assert_response :success
    assert_select "a[href=?]",
                  stores_faq_path(return_to: stores_lp_202609_return_path),
                  minimum: 2

    get stores_lp_202607_path
    assert_response :success
    assert_select "a[href^='/stores/faq']", count: 0
  end

  test "dashboard FAQ card is shown only to an exact store admin role" do
    %i[customer cast store_admin system_admin].each do |role|
      user = User.create!(
        email: "store-faq-dashboard-#{role}@example.com",
        password: "password123",
        role:
      )

      sign_in user, scope: :user
      get dashboard_path

      assert_response :success
      expected_count = role == :store_admin ? 1 : 0
      if expected_count == 1
        assert_select "a[href=?]", stores_faq_path(return_to: dashboard_path), count: 1 do
          assert_select "h5", text: "店舗向けFAQ"
        end
      else
        assert_select "a[href=?]", stores_faq_path(return_to: dashboard_path), count: 0
      end
      sign_out user
    end
  end
end
