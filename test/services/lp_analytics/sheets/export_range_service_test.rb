# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::ExportRangeServiceTest < ActiveSupport::TestCase
  test "古い日付から処理し1日失敗しても残りの日付を継続する" do
    calls = []
    factory = ->(date, lp_identifier) {
      Object.new.tap do |service|
        service.define_singleton_method(:call) do
          calls << [ date, lp_identifier ]
          raise Timeout::Error if date == Date.new(2026, 8, 8)
        end
      end
    }
    service = LpAnalytics::Sheets::ExportRangeService.new(
      start_date: "2026-08-07",
      end_date: "2026-08-09",
      export_day_factory: factory
    )

    result = service.call

    assert_equal [ Date.new(2026, 8, 7), Date.new(2026, 8, 8), Date.new(2026, 8, 9) ], calls.map(&:first)
    assert_equal [ Date.new(2026, 8, 7), Date.new(2026, 8, 9) ], result.succeeded_dates
    assert_equal [ Date.new(2026, 8, 8) ], result.failures.map(&:aggregation_date)
    refute result.success?
  end

  test "不正日付・逆転・上限超過を拒否する" do
    invalid_ranges = [
      [ "invalid", "2026-08-09" ],
      [ "20260809", "2026-08-09" ],
      [ "2026-08-10", "2026-08-09" ],
      [ "2025-08-08", "2026-08-09" ]
    ]

    invalid_ranges.each do |start_date, end_date|
      assert_raises ArgumentError do
        LpAnalytics::Sheets::ExportRangeService.new(start_date: start_date, end_date: end_date)
      end
    end
  end
end
