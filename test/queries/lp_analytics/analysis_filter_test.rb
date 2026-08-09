# frozen_string_literal: true

require "test_helper"

class LpAnalytics::AnalysisFilterTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 9)

  test "プリセット期間を日本時間の日境界へ変換する" do
    filter = LpAnalytics::AnalysisFilter.new(params: { period: "today" }, today: TODAY)

    assert_equal TODAY, filter.start_date
    assert_equal TODAY, filter.end_date
    assert_equal Time.zone.parse("2026-08-09 00:00:00"), filter.start_time
    assert_equal Time.zone.parse("2026-08-10 00:00:00"), filter.end_time

    filter = LpAnalytics::AnalysisFilter.new(params: { period: "last_30_days" }, today: TODAY)
    assert_equal Date.new(2026, 7, 11), filter.start_date
    assert_equal TODAY, filter.end_date

    filter = LpAnalytics::AnalysisFilter.new(params: { period: "last_7_days" }, today: TODAY)
    assert_equal Date.new(2026, 8, 3), filter.start_date
    assert_equal TODAY, filter.end_date
  end

  test "正しい任意期間を採用する" do
    filter = LpAnalytics::AnalysisFilter.new(
      params: { period: "custom", start_date: "2026-07-01", end_date: "2026-07-31" },
      today: TODAY
    )

    assert_equal "custom", filter.period
    assert_equal Date.new(2026, 7, 1), filter.start_date
    assert_equal Date.new(2026, 7, 31), filter.end_date
    assert_empty filter.warnings
  end

  test "不正・逆転・上限超過の任意期間を安全な初期値へ戻す" do
    invalid_params = [
      { start_date: "invalid", end_date: "2026-08-09" },
      { start_date: "2026-08-09", end_date: "2026-08-08" },
      { start_date: "2025-08-08", end_date: "2026-08-09" }
    ]

    invalid_params.each do |params|
      filter = LpAnalytics::AnalysisFilter.new(params: params.merge(period: "custom"), today: TODAY)

      assert_equal "last_7_days", filter.period
      assert_equal Date.new(2026, 8, 3), filter.start_date
      assert_equal TODAY, filter.end_date
      assert_not_empty filter.warnings
    end
  end

  test "期間・LP・流入・UTM・端末で訪問を絞り込む" do
    matching = create_visit(
      started_at: "2026-08-09 12:00:00",
      traffic_source: "meta",
      utm_source: "facebook",
      utm_campaign: "campaign_a",
      utm_content: "creative_a",
      device_type: "smartphone"
    )
    create_visit(
      started_at: "2026-08-08 12:00:00",
      traffic_source: "meta",
      utm_source: "facebook",
      utm_campaign: "campaign_a",
      utm_content: "creative_a",
      device_type: "smartphone"
    )
    create_visit(started_at: "2026-08-09 12:00:00", traffic_source: "other")

    filter = LpAnalytics::AnalysisFilter.new(
      params: {
        period: "today",
        traffic_source: "meta",
        utm_source: "facebook",
        utm_campaign: "campaign_a",
        utm_content: "creative_a",
        device_type: "smartphone"
      },
      today: TODAY
    )

    assert_equal [ matching.id ], filter.apply.pluck(:id)
  end

  test "直接・不明をnilと空文字として絞り込む" do
    nil_source = create_visit(started_at: "2026-08-09 10:00:00", traffic_source: nil)
    blank_source = create_visit(started_at: "2026-08-09 11:00:00", traffic_source: "")
    create_visit(started_at: "2026-08-09 12:00:00", traffic_source: "meta")

    filter = LpAnalytics::AnalysisFilter.new(
      params: { period: "today", traffic_source: LpAnalytics::AnalysisFilter::DIRECT_VALUE },
      today: TODAY
    )

    assert_equal [ nil_source.id, blank_source.id ].sort, filter.apply.pluck(:id).sort
  end

  private

  def create_visit(started_at:, traffic_source: "meta", device_type: "pc", **attributes)
    time = Time.zone.parse(started_at)
    LpAnalytics::Visit.create!(
      {
        lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
        traffic_source: traffic_source,
        device_type: device_type,
        browser_type: "chrome",
        started_at: time,
        last_activity_at: time
      }.merge(attributes)
    )
  end
end
