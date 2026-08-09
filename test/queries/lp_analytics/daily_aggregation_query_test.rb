# frozen_string_literal: true

require "test_helper"

class LpAnalytics::DailyAggregationQueryTest < ActiveSupport::TestCase
  TARGET_DATE = Date.new(2026, 8, 9)

  test "日本時間の訪問開始日で絞り訪問ごとのflagと回数を流入軸で集計する" do
    start_time = Time.zone.parse("2026-08-09 00:00:00")
    first = create_visit(
      started_at: start_time,
      traffic_source: "meta",
      utm_source: "facebook",
      utm_medium: "paid_social",
      utm_campaign: "campaign_a",
      utm_content: "creative_a"
    )
    second = create_visit(
      started_at: start_time + 10.hours,
      traffic_source: "meta",
      utm_source: "facebook",
      utm_medium: "paid_social",
      utm_campaign: "campaign_a",
      utm_content: "creative_a"
    )
    create_visit(started_at: start_time + 12.hours, traffic_source: nil)
    create_visit(started_at: start_time - 1.second, traffic_source: "outside_before")
    create_visit(started_at: start_time + 1.day, traffic_source: "outside_after")

    record_event(first, "scroll_reached", "25")
    record_event(first, "scroll_reached", "50")
    record_event(first, "scroll_reached", "90", occurred_at: start_time + 1.day + 1.hour)
    2.times { record_event(first, "cta_clicked", "hero_registration") }
    record_event(first, "store_registration_form_view")
    2.times { record_registration_completion(first) }
    record_event(first, "cta_clicked", "bottom_contact")
    record_event(first, "store_contact_form_view")
    2.times { record_contact_completion(first) }

    record_event(second, "scroll_reached", "25")
    record_event(second, "scroll_reached", "75")
    record_event(second, "cta_clicked", "flow_registration")
    record_event(second, "store_registration_form_view")

    rows = LpAnalytics::DailyAggregationQuery.new(aggregation_date: TARGET_DATE).call
    meta = rows.find { |row| row.traffic_source == "meta" }
    direct_row = rows.find { |row| row.traffic_source == "" }

    assert_equal 2, rows.size
    assert_equal 2, meta.visit_count
    assert_equal 2, meta.scroll_25_visit_count
    assert_equal 1, meta.scroll_50_visit_count
    assert_equal 1, meta.scroll_75_visit_count
    assert_equal 1, meta.scroll_90_visit_count
    assert_equal 2, meta.registration_cta_click_visit_count
    assert_equal 3, meta.registration_cta_click_count
    assert_equal 2, meta.registration_form_visit_count
    assert_equal 2, meta.registration_completion_count
    assert_equal 1, meta.registration_completion_visit_count
    assert_in_delta 0.5, meta.registration_cv_rate
    assert_equal 1, meta.contact_cta_click_visit_count
    assert_equal 1, meta.contact_form_visit_count
    assert_equal 2, meta.contact_completion_count
    assert_equal 1, meta.contact_completion_visit_count
    assert_in_delta 0.5, meta.contact_cv_rate

    assert_equal 1, direct_row.visit_count
    assert_equal "", direct_row.utm_source
    assert_equal 0.0, direct_row.registration_cv_rate
    assert_equal 0.0, direct_row.contact_cv_rate
    assert_match(/\A[0-9a-f]{64}\z/, direct_row.aggregation_key)
  end

  test "流入元またはUTMが異なる訪問を別行にする" do
    time = Time.zone.parse("2026-08-09 12:00:00")
    create_visit(started_at: time, traffic_source: "meta", utm_campaign: "campaign_a", utm_content: "creative_a")
    create_visit(started_at: time, traffic_source: "meta", utm_campaign: "campaign_a", utm_content: "creative_b")
    create_visit(started_at: time, traffic_source: "direct", utm_campaign: "campaign_a", utm_content: "creative_a")

    rows = LpAnalytics::DailyAggregationQuery.new(aggregation_date: TARGET_DATE).call

    assert_equal 3, rows.size
    assert_equal 3, rows.map(&:aggregation_key).uniq.size
  end

  test "23時59分台に開始して翌日00時台に完了した訪問を開始日の集計へ含める" do
    started_at = Time.zone.parse("2026-08-09 23:59:30")
    completed_at = Time.zone.parse("2026-08-10 00:00:30")
    visit = create_visit(started_at: started_at, traffic_source: "date_boundary")
    store = Store.create!(name: "日付境界店舗", lp_analytics_visit: visit)

    record_completion(
      visit,
      "store_registration_complete",
      store,
      occurred_at: completed_at
    )

    start_date_row = LpAnalytics::DailyAggregationQuery
      .new(aggregation_date: TARGET_DATE)
      .call
      .sole
    next_date_rows = LpAnalytics::DailyAggregationQuery
      .new(aggregation_date: TARGET_DATE + 1.day)
      .call

    assert_equal 1, start_date_row.visit_count
    assert_equal 1, start_date_row.registration_completion_count
    assert_equal 1, start_date_row.registration_completion_visit_count
    assert_in_delta 1.0, start_date_row.registration_cv_rate
    assert_empty next_date_rows
  end

  test "訪問がなければ空配列を返す" do
    rows = LpAnalytics::DailyAggregationQuery.new(aggregation_date: Date.new(2020, 1, 1)).call

    assert_empty rows
  end

  private

  def create_visit(started_at:, traffic_source:, **attributes)
    LpAnalytics::Visit.create!(
      {
        lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
        traffic_source: traffic_source,
        device_type: "pc",
        started_at: started_at,
        last_activity_at: started_at
      }.merge(attributes)
    )
  end

  def record_event(visit, event_type, event_value = nil, occurred_at: visit.started_at + 1.minute)
    visit.events.create!(
      event_type: event_type,
      event_value: event_value,
      lp_identifier: visit.lp_identifier,
      occurred_at: occurred_at,
      browser_event_id: SecureRandom.uuid,
      dedupe_key: LpAnalytics::Event.dedupe_key_for(event_type, event_value),
      metadata: {}
    )
  end

  def record_registration_completion(visit)
    store = Store.create!(name: "日次集計店舗#{SecureRandom.hex(3)}", lp_analytics_visit: visit)
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

  def record_completion(
    visit,
    event_type,
    completion_record,
    occurred_at: visit.started_at + 2.minutes
  )
    visit.events.create!(
      event_type: event_type,
      lp_identifier: visit.lp_identifier,
      occurred_at: occurred_at,
      completion_record: completion_record,
      metadata: {}
    )
  end
end
