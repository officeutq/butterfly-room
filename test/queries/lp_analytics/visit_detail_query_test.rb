# frozen_string_literal: true

require "test_helper"

class LpAnalytics::VisitDetailQueryTest < ActiveSupport::TestCase
  test "同時刻のイベントをid順で返し最終到達地点と結果を判定する" do
    time = Time.zone.parse("2026-08-09 10:00:00")
    visit = LpAnalytics::Visit.create!(
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      device_type: "pc",
      started_at: time,
      last_activity_at: time
    )
    first = create_event(visit, "scroll_reached", "25", time)
    second = create_event(visit, "section_reached", "PRICING", time)
    third = create_event(visit, "cta_clicked", "hero_registration", time)

    result = LpAnalytics::VisitDetailQuery.new(public_id: visit.public_id).call

    assert_equal [ first.id, second.id, third.id ], result.events.map(&:id)
    assert_equal second, result.final_reach_event
    assert_equal third, result.final_result_event
  end

  test "不正または存在しない訪問IDはnot foundにする" do
    assert_raises ActiveRecord::RecordNotFound do
      LpAnalytics::VisitDetailQuery.new(public_id: "invalid").call
    end
  end

  test "完了後にCTA操作があっても最終結果は完了を優先する" do
    time = Time.zone.parse("2026-08-09 10:00:00")
    visit = LpAnalytics::Visit.create!(
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      device_type: "pc",
      started_at: time,
      last_activity_at: time
    )
    store = Store.create!(name: "結果判定店舗", lp_analytics_visit: visit)
    completion = visit.events.create!(
      event_type: "store_registration_complete",
      lp_identifier: visit.lp_identifier,
      occurred_at: time + 1.minute,
      completion_record: store,
      metadata: {}
    )
    create_event(visit, "cta_clicked", "hero_registration", time + 2.minutes)

    result = LpAnalytics::VisitDetailQuery.new(public_id: visit.public_id).call

    assert_equal completion, result.final_result_event
  end

  private

  def create_event(visit, event_type, event_value, occurred_at)
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
end
