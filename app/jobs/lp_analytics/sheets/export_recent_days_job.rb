# frozen_string_literal: true

module LpAnalytics
  module Sheets
    class ExportRecentDaysJob < ApplicationJob
      class BatchExportError < StandardError; end

      queue_as :default

      DAYS = 7

      def perform(today: Time.zone.today)
        settings = Settings.from_env
        unless settings.automatic_export_enabled?
          Rails.logger.info("[LpAnalyticsSheetsExport] skipped automatic export disabled")
          return
        end

        end_date = strict_date(today) - 1.day
        start_date = end_date - (DAYS - 1).days
        result = ExportRangeService.new(start_date: start_date, end_date: end_date).call
        return result if result.success?

        failed_dates = result.failures.map { |failure| failure.aggregation_date.iso8601 }.uniq.join(",")
        Rails.logger.error("[LpAnalyticsSheetsExport] batch failed dates=#{failed_dates}")
        raise BatchExportError, "LP analytics Sheets export failed for #{result.failures.length} target(s)"
      end

      private

      def strict_date(value)
        return value if value.instance_of?(Date)

        raw = value.to_s
        raise Date::Error unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        Date.iso8601(raw)
      rescue Date::Error
        raise ArgumentError, "today must be YYYY-MM-DD"
      end
    end
  end
end
