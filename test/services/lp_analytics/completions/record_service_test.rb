# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Completions::RecordServiceTest < ActiveSupport::TestCase
  setup do
    @started_at = Time.zone.parse("2026-08-09 12:00:00")
    @visit = LpAnalytics::Visit.create!(
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      traffic_source: "meta",
      device_type: "pc",
      browser_type: "chrome",
      started_at: @started_at,
      last_activity_at: @started_at
    )
  end

  test "正常保存された店舗を根拠に登録完了を記録する" do
    store = Store.create!(name: "登録完了店舗", lp_analytics_visit: @visit)
    now = @started_at + 5.minutes
    result = nil

    assert_difference -> { LpAnalytics::Event.count }, 1 do
      result = record(
        event_type: "store_registration_complete",
        completion_record: store,
        now: now
      )
    end

    refute result.duplicate
    assert_nil result.error
    assert_equal store, result.event.completion_record
    assert_equal @visit, result.event.visit
    assert_equal({}, result.event.metadata)
    assert_equal now, @visit.reload.last_activity_at
  end

  test "正常保存された問い合わせを根拠に問い合わせ完了を記録する" do
    submission = create_contact_submission!(lp_analytics_visit: @visit)

    assert_difference -> { LpAnalytics::Event.count }, 1 do
      result = record(
        event_type: "store_contact_complete",
        completion_record: submission
      )

      assert_nil result.error
      assert_equal submission, result.event.completion_record
    end
  end

  test "同じ業務レコードの再処理は完了イベントを重複させない" do
    store = Store.create!(name: "重複防止店舗", lp_analytics_visit: @visit)
    first_result = record(
      event_type: "store_registration_complete",
      completion_record: store
    )
    duplicate_result = nil

    assert_no_difference -> { LpAnalytics::Event.count } do
      duplicate_result = record(
        event_type: "store_registration_complete",
        completion_record: store
      )
    end

    assert duplicate_result.duplicate
    assert_equal first_result.event, duplicate_result.event
  end

  test "完了件数と完了訪問数を区別できる" do
    2.times do |index|
      store = Store.create!(name: "複数登録店舗#{index}", lp_analytics_visit: @visit)
      record(event_type: "store_registration_complete", completion_record: store)
    end

    events = LpAnalytics::Event.where(event_type: "store_registration_complete")
    assert_equal 2, events.count
    assert_equal 1, events.distinct.count(:lp_analytics_visit_id)
  end

  test "訪問と紐付かない業務レコードでは完了を記録せず個人情報をログへ出さない" do
    submission = create_contact_submission!(lp_analytics_visit: nil)
    result = nil
    log_output = StringIO.new
    logger = Logger.new(log_output)

    assert_no_difference -> { LpAnalytics::Event.count } do
      result = LpAnalytics::Completions::RecordService.new(
        visit: @visit,
        event_type: "store_contact_complete",
        completion_record: submission,
        logger: logger
      ).call
    end

    assert_instance_of ArgumentError, result.error
    assert_nil result.event
    assert_includes log_output.string, "lp_analytics_completion_record_failed"
    refute_includes log_output.string, submission.name
    refute_includes log_output.string, submission.email
    refute_includes log_output.string, submission.phone_number
  end

  private

  def record(event_type:, completion_record:, now: @started_at + 1.minute)
    LpAnalytics::Completions::RecordService.new(
      visit: @visit,
      event_type: event_type,
      completion_record: completion_record,
      now: now
    ).call
  end

  def create_contact_submission!(lp_analytics_visit:)
    StoreContactSubmission.create!(
      name: "Owner Name",
      store_name: "Sample Store",
      email: "owner@example.com",
      phone_number: "090-1234-5678",
      lp_analytics_visit: lp_analytics_visit
    )
  end
end
