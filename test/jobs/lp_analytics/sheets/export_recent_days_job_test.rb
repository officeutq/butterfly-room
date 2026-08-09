# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::ExportRecentDaysJobTest < ActiveJob::TestCase
  TODAY = Date.new(2026, 8, 10)

  test "flag無効時は集計・外部接続せず終了する" do
    settings = build_settings(enabled: false)

    with_singleton_method(LpAnalytics::Sheets::Settings, :from_env, -> { settings }) do
      with_singleton_method(LpAnalytics::Sheets::ExportRangeService, :new, ->(**) { flunk "range export must not be created" }) do
        assert_nil LpAnalytics::Sheets::ExportRecentDaysJob.perform_now(today: TODAY)
      end
    end
  end

  test "前日を含む直近7日を古い日付から処理する" do
    settings = build_settings(enabled: true)
    captured = nil
    range_result = LpAnalytics::Sheets::ExportRangeService::Result.new(
      succeeded_dates: (Date.new(2026, 8, 3)..Date.new(2026, 8, 9)).to_a,
      failures: []
    )
    range_service = Object.new
    range_service.define_singleton_method(:call) { range_result }

    with_singleton_method(LpAnalytics::Sheets::Settings, :from_env, -> { settings }) do
      factory = ->(**arguments) { captured = arguments; range_service }
      with_singleton_method(LpAnalytics::Sheets::ExportRangeService, :new, factory) do
        result = LpAnalytics::Sheets::ExportRecentDaysJob.perform_now(today: TODAY)

        assert result.success?
      end
    end

    assert_equal Date.new(2026, 8, 3), captured.fetch(:start_date)
    assert_equal Date.new(2026, 8, 9), captured.fetch(:end_date)
  end

  test "全日を試行した結果に失敗があればJobを失敗させる" do
    settings = build_settings(enabled: true)
    failure = LpAnalytics::Sheets::ExportRangeService::Failure.new(
      aggregation_date: Date.new(2026, 8, 8),
      error_class: "Timeout::Error"
    )
    range_result = LpAnalytics::Sheets::ExportRangeService::Result.new(
      succeeded_dates: [ Date.new(2026, 8, 9) ],
      failures: [ failure ]
    )
    range_service = Object.new
    range_service.define_singleton_method(:call) { range_result }

    with_singleton_method(LpAnalytics::Sheets::Settings, :from_env, -> { settings }) do
      with_singleton_method(LpAnalytics::Sheets::ExportRangeService, :new, ->(**) { range_service }) do
        assert_raises(LpAnalytics::Sheets::ExportRecentDaysJob::BatchExportError) do
          LpAnalytics::Sheets::ExportRecentDaysJob.perform_now(today: TODAY)
        end
      end
    end
  end

  private

  def with_singleton_method(target, method_name, replacement)
    original = target.method(method_name)
    target.define_singleton_method(method_name, &replacement)
    yield
  ensure
    target.singleton_class.send(:define_method, method_name, original)
  end

  def build_settings(enabled:)
    LpAnalytics::Sheets::Settings.new(
      enabled: enabled,
      region: "ap-northeast-1",
      spreadsheet_id: "dummy-spreadsheet-id",
      worksheet_name: "daily_raw",
      credentials_secret_id: "dummy-secret-id",
      rails_environment: "production"
    )
  end
end
