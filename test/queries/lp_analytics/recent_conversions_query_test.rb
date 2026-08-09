# frozen_string_literal: true

require "test_helper"

class LpAnalytics::RecentConversionsQueryTest < ActiveSupport::TestCase
  test "完了イベントを新しい順で重複なくページングする" do
    campaign = "recent-#{SecureRandom.hex(4)}"
    older = create_completion(campaign: campaign, occurred_at: Time.zone.parse("2026-08-09 10:00:00"))
    newer = create_completion(campaign: campaign, occurred_at: Time.zone.parse("2026-08-09 11:00:00"))
    filter = LpAnalytics::AnalysisFilter.new(
      params: {
        period: "custom",
        start_date: "2026-08-09",
        end_date: "2026-08-09",
        utm_campaign: campaign
      },
      today: Date.new(2026, 8, 9)
    )

    first = LpAnalytics::RecentConversionsQuery.new(filter: filter, page: 1, per_page: 1).call
    second = LpAnalytics::RecentConversionsQuery.new(filter: filter, page: 2, per_page: 1).call

    assert_equal [ newer.id ], first.records.map(&:id)
    assert_equal [ older.id ], second.records.map(&:id)
    assert_equal 2, first.total_count
    assert_equal 2, first.total_pages
    assert_equal 2, first.next_page
    assert_equal 1, second.previous_page
  end

  private

  def create_completion(campaign:, occurred_at:)
    visit = LpAnalytics::Visit.create!(
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      utm_campaign: campaign,
      device_type: "pc",
      started_at: occurred_at - 1.minute,
      last_activity_at: occurred_at
    )
    store = Store.create!(name: "ページング店舗#{SecureRandom.hex(2)}", lp_analytics_visit: visit)
    visit.events.create!(
      event_type: "store_registration_complete",
      lp_identifier: visit.lp_identifier,
      occurred_at: occurred_at,
      completion_record: store,
      metadata: {}
    )
  end
end
