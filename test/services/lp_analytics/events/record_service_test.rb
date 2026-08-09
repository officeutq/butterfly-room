# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Events::RecordServiceTest < ActiveSupport::TestCase
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

  test "許可されたイベントを保存して訪問の最終操作日時を更新する" do
    now = @started_at + 1.minute
    result = nil

    assert_difference "LpAnalytics::Event.count", 1 do
      result = record(
        event_type: "scroll_reached",
        event_value: "25",
        browser_event_id: SecureRandom.uuid,
        metadata: { viewport_type: "pc" },
        now: now
      )
    end

    refute result.duplicate
    assert_equal "scroll_reached", result.event.event_type
    assert_equal "25", result.event.event_value
    assert_equal({ "viewport_type" => "pc" }, result.event.metadata)
    assert_equal now, @visit.reload.last_activity_at
  end

  test "同じブラウザイベントUUIDの再送はDB一意制約で1件にする" do
    event_id = SecureRandom.uuid
    first_result = record(event_type: "cta_clicked", event_value: "hero_registration", browser_event_id: event_id)
    duplicate_result = nil

    assert_no_difference "LpAnalytics::Event.count" do
      duplicate_result = record(
        event_type: "cta_clicked",
        event_value: "hero_registration",
        browser_event_id: event_id
      )
    end

    refute first_result.duplicate
    assert duplicate_result.duplicate
    assert_equal first_result.event.id, duplicate_result.event.id
  end

  test "スクロール・セクション・CTA位置到達は訪問内で重複しない" do
    cases = [
      [ "scroll_reached", "50" ],
      [ "section_reached", "PRICING" ],
      [ "cta_reached", "bottom_registration" ]
    ]

    cases.each do |event_type, event_value|
      first_result = record(
        event_type: event_type,
        event_value: event_value,
        browser_event_id: SecureRandom.uuid
      )
      duplicate_result = nil

      assert_no_difference "LpAnalytics::Event.count", event_type do
        duplicate_result = record(
          event_type: event_type,
          event_value: event_value,
          browser_event_id: SecureRandom.uuid
        )
      end

      refute first_result.duplicate
      assert duplicate_result.duplicate
      assert_equal first_result.event.id, duplicate_result.event.id
    end
  end

  test "CTAクリックとFAQ操作は複数回保存する" do
    assert_difference "LpAnalytics::Event.count", 4 do
      2.times do
        record(
          event_type: "cta_clicked",
          event_value: "bottom_contact",
          browser_event_id: SecureRandom.uuid
        )
        record(
          event_type: "faq_opened",
          event_value: "faq_1",
          browser_event_id: SecureRandom.uuid
        )
      end
    end
  end

  test "未許可のevent type・value・metadataを保存しない" do
    invalid_attributes = [
      { event_type: "arbitrary", event_value: nil, metadata: {} },
      { event_type: "scroll_reached", event_value: "100", metadata: {} },
      { event_type: "cta_clicked", event_value: "unknown_cta", metadata: {} },
      { event_type: "lp_view", event_value: { email: "owner@example.com" }, metadata: {} },
      { event_type: "lp_view", event_value: nil, metadata: { email: "owner@example.com" } },
      { event_type: "lp_view", event_value: nil, metadata: { viewport_type: { nested: true } } }
    ]

    assert_no_difference "LpAnalytics::Event.count" do
      invalid_attributes.each do |attributes|
        assert_raises(LpAnalytics::Events::RecordService::InvalidEventError) do
          record(**attributes, browser_event_id: SecureRandom.uuid)
        end
      end
    end
  end

  test "ブラウザイベントUUIDはUUID形式のみ許可する" do
    assert_no_difference "LpAnalytics::Event.count" do
      [ "not-a-uuid", "", 123 ].each do |browser_event_id|
        assert_raises(LpAnalytics::Events::RecordService::InvalidEventError) do
          record(event_type: "lp_view", browser_event_id: browser_event_id)
        end
      end
    end
  end

  test "イベントテーブルに個人情報・raw User-Agent・IPの列を持たない" do
    %w[
      user_agent raw_user_agent ip_address name email phone_number form_payload request_payload
    ].each do |column|
      refute_includes LpAnalytics::Event.column_names, column
    end
  end

  private

  def record(
    event_type:,
    event_value: nil,
    browser_event_id: nil,
    metadata: {},
    now: @started_at + 1.minute
  )
    LpAnalytics::Events::RecordService.new(
      visit: @visit,
      event_type: event_type,
      event_value: event_value,
      browser_event_id: browser_event_id,
      metadata: metadata,
      now: now
    ).call
  end
end
