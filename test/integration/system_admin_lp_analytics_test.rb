# frozen_string_literal: true

require "test_helper"

class SystemAdminLpAnalyticsTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "lp_analysis_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "lp_analysis_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "lp_analysis_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "lp_analysis_system_admin@example.com", password: "password", role: :system_admin)
    @started_at = Time.zone.now.change(usec: 0) - 1.hour
    @visit = create_visit
    create_event("lp_view", occurred_at: @started_at)
    create_event("scroll_reached", event_value: "25", occurred_at: @started_at + 1.minute)
    create_event("section_reached", event_value: "PRICING", occurred_at: @started_at + 2.minutes)
    create_event("cta_reached", event_value: "hero_registration", occurred_at: @started_at + 3.minutes)
    create_event("cta_clicked", event_value: "hero_registration", occurred_at: @started_at + 4.minutes)
    create_event("store_registration_form_view", occurred_at: @started_at + 5.minutes)
    create_registration_completion
  end

  test "guestはログインへ遷移する" do
    get system_admin_lp_analytics_path
    assert_redirected_to new_user_session_path

    get system_admin_lp_analytics_visit_path(@visit.public_id)
    assert_redirected_to new_user_session_path
  end

  test "system_admin以外は一覧と詳細へアクセスできない" do
    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get system_admin_lp_analytics_path
      assert_response :forbidden

      get system_admin_lp_analytics_visit_path(@visit.public_id)
      assert_response :forbidden

      sign_out :user
    end
  end

  test "system_adminのダッシュボードだけにLP行動分析導線を表示する" do
    sign_in @system_admin, scope: :user
    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", system_admin_lp_analytics_path, text: /LP行動分析/

    sign_out :user
    sign_in @customer, scope: :user
    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", system_admin_lp_analytics_path, count: 0
  end

  test "system_adminがKPI・ファネル・到達率・CTA分析・匿名完了一覧を確認できる" do
    sign_in @system_admin, scope: :user

    get system_admin_lp_analytics_path, params: {
      period: "custom",
      start_date: @started_at.to_date.iso8601,
      end_date: @started_at.to_date.iso8601,
      utm_campaign: @visit.utm_campaign
    }

    assert_response :success
    assert_select "h1", "LP行動分析"
    assert_select "h2", text: "KPI"
    assert_select "h2", text: "店舗登録ファネル"
    assert_select "h2", text: "お問い合わせファネル"
    assert_select "h2", text: "スクロール到達率"
    assert_select "h2", text: "セクション到達率"
    assert_select "h2", text: "CTA別分析"
    assert_select "h2", text: "最近のコンバージョン"
    assert_select "a[href=?]", system_admin_lp_analytics_visit_path(@visit.public_id), text: "訪問詳細"
    assert_includes response.body, @visit.utm_campaign
    assert_includes response.body, "creative-system-test"
    assert_not_includes response.body, "secret-owner@example.com"
    assert_not_includes response.body, "090-1111-2222"
  end

  test "不正な期間指定を安全に初期期間へ戻す" do
    sign_in @system_admin, scope: :user

    get system_admin_lp_analytics_path, params: {
      period: "custom",
      start_date: "not-a-date",
      end_date: "2026-08-09"
    }

    assert_response :success
    assert_select ".alert-warning", text: /正しい日付/
    assert_select "select[name=period] option[selected][value=last_7_days]"
  end

  test "system_adminが匿名訪問属性と時系列の行動履歴だけを確認できる" do
    sign_in @system_admin, scope: :user

    get system_admin_lp_analytics_visit_path(@visit.public_id)

    assert_response :success
    assert_select "h1", "LP匿名訪問詳細"
    assert_includes response.body, @visit.public_id
    assert_includes response.body, @visit.utm_source
    assert_includes response.body, @visit.referral_code
    assert_includes response.body, "スクロール到達: 25"
    assert_includes response.body, "セクション到達: PRICING"
    assert_includes response.body, "店舗登録完了"
    assert_operator response.body.index("スクロール到達: 25"), :<, response.body.index("セクション到達: PRICING")
    assert_not_includes response.body, "secret-owner@example.com"
    assert_not_includes response.body, "090-1111-2222"
  end

  private

  def create_visit
    LpAnalytics::Visit.create!(
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      traffic_source: "meta",
      utm_source: "facebook",
      utm_medium: "paid_social",
      utm_campaign: "system-admin-#{SecureRandom.hex(4)}",
      utm_content: "creative-system-test",
      referral_code: "ref-system-test",
      device_type: "smartphone",
      browser_type: "chrome",
      started_at: @started_at,
      last_activity_at: @started_at
    )
  end

  def create_event(event_type, event_value: nil, occurred_at:)
    @visit.events.create!(
      event_type: event_type,
      event_value: event_value,
      lp_identifier: @visit.lp_identifier,
      occurred_at: occurred_at,
      browser_event_id: SecureRandom.uuid,
      dedupe_key: LpAnalytics::Event.dedupe_key_for(event_type, event_value),
      metadata: {}
    )
  end

  def create_registration_completion
    store = Store.create!(name: "匿名集計用店舗", lp_analytics_visit: @visit)
    @visit.events.create!(
      event_type: "store_registration_complete",
      lp_identifier: @visit.lp_identifier,
      occurred_at: @started_at + 6.minutes,
      completion_record: store,
      metadata: {}
    )

    StoreContactSubmission.create!(
      name: "表示禁止氏名",
      store_name: "表示禁止店舗",
      email: "secret-owner@example.com",
      phone_number: "090-1111-2222",
      lp_analytics_visit: @visit
    )
  end
end
