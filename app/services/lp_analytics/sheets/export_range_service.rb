# frozen_string_literal: true

module LpAnalytics
  module Sheets
    class ExportRangeService
      MAX_RANGE_DAYS = 366
      Result = Data.define(:succeeded_dates, :failures) do
        def success?
          failures.empty?
        end
      end
      Failure = Data.define(:aggregation_date, :error_class)

      def initialize(
        start_date:,
        end_date:,
        lp_identifiers: Configuration::LP_DEFINITIONS.keys,
        export_day_factory: nil
      )
        @start_date = strict_date(start_date)
        @end_date = strict_date(end_date)
        @lp_identifiers = lp_identifiers
        @export_day_factory = export_day_factory || ->(date, lp_identifier) {
          ExportDayService.new(aggregation_date: date, lp_identifier: lp_identifier)
        }
        validate_range!
      end

      def call
        succeeded_dates = []
        failures = []

        (start_date..end_date).each do |date|
          day_succeeded = true
          lp_identifiers.each do |lp_identifier|
            export_day_factory.call(date, lp_identifier).call
          rescue StandardError => error
            day_succeeded = false
            failures << Failure.new(aggregation_date: date, error_class: error.class.name)
          end
          succeeded_dates << date if day_succeeded
        end

        Result.new(succeeded_dates: succeeded_dates, failures: failures)
      end

      private

      attr_reader :start_date, :end_date, :lp_identifiers, :export_day_factory

      def validate_range!
        raise ArgumentError, "start date must not be after end date" if start_date > end_date
        raise ArgumentError, "date range must be #{MAX_RANGE_DAYS} days or less" if (end_date - start_date).to_i + 1 > MAX_RANGE_DAYS
      end

      def strict_date(value)
        return value if value.instance_of?(Date)

        raw = value.to_s
        raise Date::Error unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        Date.iso8601(raw)
      rescue Date::Error
        raise ArgumentError, "date must be YYYY-MM-DD"
      end
    end
  end
end
