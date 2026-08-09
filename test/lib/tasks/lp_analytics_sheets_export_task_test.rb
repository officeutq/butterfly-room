# frozen_string_literal: true

require "test_helper"
require "rake"

class LpAnalyticsSheetsExportTaskTest < ActiveSupport::TestCase
  DATE_TASK = "lp_analytics:sheets:export_date"
  RANGE_TASK = "lp_analytics:sheets:export_range"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(DATE_TASK)
    Rake::Task[DATE_TASK].reenable
    Rake::Task[RANGE_TASK].reenable
  end

  test "指定日を同じServiceへ渡してsummaryを表示する" do
    captured = nil
    result = successful_result(Date.new(2026, 8, 9))
    service = Object.new
    service.define_singleton_method(:call) { result }

    factory = ->(**arguments) { captured = arguments; service }
    out = nil
    with_singleton_method(LpAnalytics::Sheets::ExportRangeService, :new, factory) do
      out, = capture_io { Rake::Task[DATE_TASK].invoke("2026-08-09") }
    end

    assert_equal Date.new(2026, 8, 9), captured.fetch(:start_date)
    assert_equal Date.new(2026, 8, 9), captured.fetch(:end_date)
    assert_includes out, "succeeded=1 failed=0"
    assert_includes out, "succeeded_dates=2026-08-09"
  end

  test "期間を同じServiceへ渡す" do
    captured = nil
    result = successful_result(Date.new(2026, 8, 1), Date.new(2026, 8, 2))
    service = Object.new
    service.define_singleton_method(:call) { result }

    factory = ->(**arguments) { captured = arguments; service }
    with_singleton_method(LpAnalytics::Sheets::ExportRangeService, :new, factory) do
      capture_io { Rake::Task[RANGE_TASK].invoke("2026-08-01", "2026-08-02") }
    end

    assert_equal Date.new(2026, 8, 1), captured.fetch(:start_date)
    assert_equal Date.new(2026, 8, 2), captured.fetch(:end_date)
  end

  test "不正日付は非0相当で終了する" do
    [ "invalid", "20260809" ].each do |date|
      Rake::Task[DATE_TASK].reenable
      _, error = capture_io do
        assert_raises(SystemExit) { Rake::Task[DATE_TASK].invoke(date) }
      end

      assert_includes error, "date must be YYYY-MM-DD"
    end
  end

  test "1日でも失敗した場合はsummaryを表示して非0相当で終了する" do
    failure = LpAnalytics::Sheets::ExportRangeService::Failure.new(
      aggregation_date: Date.new(2026, 8, 9),
      error_class: "Timeout::Error"
    )
    result = LpAnalytics::Sheets::ExportRangeService::Result.new(succeeded_dates: [], failures: [ failure ])
    service = Object.new
    service.define_singleton_method(:call) { result }

    out = error = nil
    with_singleton_method(LpAnalytics::Sheets::ExportRangeService, :new, ->(**) { service }) do
      out, error = capture_io do
        assert_raises(SystemExit) { Rake::Task[DATE_TASK].invoke("2026-08-09") }
      end
    end

    assert_includes out, "succeeded=0 failed=1"
    assert_includes out, "2026-08-09:Timeout::Error"
    assert_includes error, "export failed"
  end

  private

  def with_singleton_method(target, method_name, replacement)
    original = target.method(method_name)
    target.define_singleton_method(method_name, &replacement)
    yield
  ensure
    target.singleton_class.send(:define_method, method_name, original)
  end

  def successful_result(*dates)
    LpAnalytics::Sheets::ExportRangeService::Result.new(succeeded_dates: dates, failures: [])
  end
end
