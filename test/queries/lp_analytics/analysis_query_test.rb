# frozen_string_literal: true

require "test_helper"

class LpAnalytics::AnalysisQueryTest < ActiveSupport::TestCase
  setup do
    @base_time = Time.zone.parse("2026-08-09 10:00:00")
    @campaign = "issue1031-#{SecureRandom.hex(4)}"
    @visit_a = create_visit(traffic_source: "meta", device_type: "smartphone")
    @visit_b = create_visit(traffic_source: "meta", device_type: "pc", started_at: @base_time + 1.hour)
    @visit_c = create_visit(traffic_source: nil, device_type: "pc", started_at: @base_time + 2.hours)
    create_visit(traffic_source: "meta", started_at: @base_time - 2.days)

    record_browser_event(@visit_a, "lp_view")
    %w[25 50 75].each { |value| record_browser_event(@visit_a, "scroll_reached", value) }
    %w[USAGE PRICING bottom_cta].each { |value| record_browser_event(@visit_a, "section_reached", value) }
    record_browser_event(@visit_a, "cta_reached", "hero_registration")
    2.times { record_browser_event(@visit_a, "cta_clicked", "hero_registration") }
    record_browser_event(@visit_a, "store_registration_form_view")
    2.times { record_registration_completion(@visit_a) }
    record_browser_event(@visit_a, "cta_reached", "bottom_contact")
    record_browser_event(@visit_a, "cta_clicked", "bottom_contact")
    record_browser_event(@visit_a, "store_contact_form_view")
    record_contact_completion(@visit_a)

    record_browser_event(@visit_b, "scroll_reached", "25")
    record_browser_event(@visit_b, "section_reached", "USAGE")
    record_browser_event(@visit_b, "cta_reached", "flow_registration")
    record_browser_event(@visit_b, "cta_clicked", "flow_registration")
  end

  test "訪問フラグと総イベント数を分離してKPIを集計する" do
    result = query.call
    kpis = result.kpis.index_by(&:key)

    assert_equal 3, result.visit_count
    assert_equal 2, kpis.fetch(:cta_clicked_visits).count
    assert_equal 1, kpis.fetch(:registration_form_visits).count
    assert_equal 2, kpis.fetch(:registration_completions).count
    assert_equal "完了訪問数: 1", kpis.fetch(:registration_completions).supplement
    assert_in_delta 33.33, kpis.fetch(:registration_completions).rate
    assert_equal 1, kpis.fetch(:contact_form_visits).count
    assert_equal 1, kpis.fetch(:contact_completions).count
    assert_in_delta 33.33, kpis.fetch(:contact_completions).rate
  end

  test "ファネルを前段到達済み訪問の連続集合として集計する" do
    result = query.call

    assert_equal [ 3, 2, 2, 2, 1, 1 ], result.registration_funnel.map(&:visit_count)
    assert_equal [ 3, 1, 1, 1, 1 ], result.contact_funnel.map(&:visit_count)
    assert result.registration_funnel.each_cons(2).all? { |previous, current| previous.visit_count >= current.visit_count }
    assert_in_delta 50.0, result.registration_funnel.fetch(4).previous_rate
  end

  test "スクロール・セクション・CTA別の訪問数と総クリック数を集計する" do
    result = query.call
    scrolls = result.scroll_metrics.index_by(&:key)
    sections = result.section_metrics.index_by(&:key)
    ctas = result.cta_metrics.index_by(&:key)

    assert_equal 2, scrolls.fetch("25").visit_count
    assert_equal 1, scrolls.fetch("50").visit_count
    assert_equal 0, scrolls.fetch("90").visit_count
    assert_equal 2, sections.fetch("USAGE").visit_count
    assert_equal 1, sections.fetch("PRICING").visit_count

    hero = ctas.fetch("hero_registration")
    assert_equal 1, hero.reached_visit_count
    assert_equal 1, hero.clicked_visit_count
    assert_equal 2, hero.click_count
    assert_in_delta 100.0, hero.click_rate
    assert_equal 0.0, ctas.fetch("bottom_registration").click_rate
  end

  test "流入条件で集計対象を絞り込む" do
    result = query(traffic_source: "meta", device_type: "smartphone").call

    assert_equal 1, result.visit_count
    assert_equal 2, result.kpis.index_by(&:key).fetch(:registration_completions).count
  end

  test "対象訪問が0件でも全比率を0として返す" do
    result = query(utm_content: "not-found").call

    assert_equal 0, result.visit_count
    assert result.kpis.filter_map(&:rate).all?(&:zero?)
    assert result.registration_funnel.all? { |metric| metric.overall_rate.zero? }
    assert result.contact_funnel.all? { |metric| metric.overall_rate.zero? }
    assert result.scroll_metrics.all? { |metric| metric.overall_rate.zero? }
    assert result.section_metrics.all? { |metric| metric.overall_rate.zero? }
    assert result.cta_metrics.all? { |metric| metric.click_rate.zero? }
  end

  test "対象訪問が増えてもSELECTクエリ数が増えない" do
    baseline_query_count = count_select_queries { query.call }

    50.times do |index|
      create_visit(
        traffic_source: "meta",
        started_at: @base_time + index.minutes
      )
    end

    increased_query_count = count_select_queries { query.call }

    assert_operator baseline_query_count, :positive?
    assert_equal baseline_query_count, increased_query_count
  end

  test "202609版のsection・CTA定義だけを表示して集計する" do
    visit = create_visit(
      traffic_source: "meta",
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202609
    )
    record_browser_event(visit, "section_reached", "existing_customer_opportunity")
    record_browser_event(visit, "section_reached", "final_opportunity_cta")
    record_browser_event(visit, "cta_reached", "hero_faq")
    record_browser_event(visit, "cta_clicked", "hero_faq")
    record_browser_event(visit, "cta_reached", "bottom_contact")
    record_browser_event(visit, "cta_clicked", "bottom_contact")

    result = query(lp_identifier: LpAnalytics::Configuration::STORE_LP_202609).call

    assert_equal 1, result.visit_count
    assert_equal LpAnalytics::Configuration::STORE_LP_202609_SECTION_LABELS.keys,
                 result.section_metrics.map(&:key)
    assert_equal LpAnalytics::Configuration::STORE_LP_202609_CTA_DEFINITIONS.keys,
                 result.cta_metrics.map(&:key)
    assert_equal :faq, result.cta_metrics.index_by(&:key).fetch("hero_faq").kind
    assert_equal [ 1, 1, 1, 0, 0 ], result.contact_funnel.map(&:visit_count)
  end

  private

  def query(**params)
    filter = LpAnalytics::AnalysisFilter.new(
      params: {
        period: "custom",
        start_date: "2026-08-09",
        end_date: "2026-08-09",
        utm_campaign: @campaign
      }.merge(params),
      today: Date.new(2026, 8, 9)
    )
    LpAnalytics::AnalysisQuery.new(filter: filter)
  end

  def create_visit(
    traffic_source:,
    device_type: "pc",
    started_at: @base_time,
    lp_identifier: LpAnalytics::Configuration::STORE_LP_202607
  )
    LpAnalytics::Visit.create!(
      lp_identifier: lp_identifier,
      traffic_source: traffic_source,
      utm_source: "facebook",
      utm_medium: "paid_social",
      utm_campaign: @campaign,
      utm_content: "creative_a",
      device_type: device_type,
      browser_type: "chrome",
      started_at: started_at,
      last_activity_at: started_at
    )
  end

  def record_browser_event(visit, event_type, event_value = nil)
    visit.events.create!(
      event_type: event_type,
      event_value: event_value,
      lp_identifier: visit.lp_identifier,
      occurred_at: visit.started_at + 1.minute,
      browser_event_id: SecureRandom.uuid,
      dedupe_key: LpAnalytics::Event.dedupe_key_for(event_type, event_value),
      metadata: {}
    )
  end

  def record_registration_completion(visit)
    store = Store.create!(name: "登録店舗#{SecureRandom.hex(2)}", lp_analytics_visit: visit)
    record_completion(visit, "store_registration_complete", store)
  end

  def record_contact_completion(visit)
    submission = StoreContactSubmission.create!(
      name: "非表示氏名",
      store_name: "非表示店舗",
      email: "private@example.com",
      phone_number: "090-0000-0000",
      lp_analytics_visit: visit
    )
    record_completion(visit, "store_contact_complete", submission)
  end

  def record_completion(visit, event_type, record)
    visit.events.create!(
      event_type: event_type,
      lp_identifier: visit.lp_identifier,
      occurred_at: visit.started_at + 2.minutes,
      completion_record: record,
      metadata: {}
    )
  end

  def count_select_queries
    count = 0
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s.lstrip
      next if payload[:cached] || payload[:name] == "SCHEMA"
      next unless sql.start_with?("SELECT", "WITH")

      count += 1
    end

    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        yield
      end
    end

    count
  end
end
