# frozen_string_literal: true

module LpAnalyticsSheetsExportTask
  Result = Data.define(:lines, :success) unless const_defined?(:Result, false)

  module_function

  def call(start_date:, end_date:)
    result = LpAnalytics::Sheets::ExportRangeService.new(start_date: start_date, end_date: end_date).call
    succeeded = result.succeeded_dates.map(&:iso8601)
    failures = result.failures.map { |failure| "#{failure.aggregation_date.iso8601}:#{failure.error_class}" }
    lines = [
      "[LpAnalyticsSheetsExport] summary " \
      "start_date=#{start_date} end_date=#{end_date} " \
      "succeeded=#{succeeded.length} failed=#{failures.length}",
      "[LpAnalyticsSheetsExport] succeeded_dates=#{succeeded.join(',')}"
    ]
    lines << "[LpAnalyticsSheetsExport] failures=#{failures.join(',')}" if failures.any?

    Result.new(lines: lines, success: result.success?)
  end

  def strict_date(value, argument_name:)
    raw = value.to_s
    raise ArgumentError, "#{argument_name} is required (YYYY-MM-DD)" if raw.blank?
    raise ArgumentError, "#{argument_name} must be YYYY-MM-DD" unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(raw)
  rescue Date::Error
    raise ArgumentError, "#{argument_name} must be YYYY-MM-DD"
  end
end

namespace :lp_analytics do
  namespace :sheets do
    desc "Export one JST date to the managed Google Sheets worksheet"
    task :export_date, [ :date ] => :environment do |_task, args|
      date = LpAnalyticsSheetsExportTask.strict_date(args[:date], argument_name: "date")
      result = LpAnalyticsSheetsExportTask.call(start_date: date, end_date: date)
      result.lines.each { |line| puts line }
      abort "[LpAnalyticsSheetsExport] export failed" unless result.success
    rescue ArgumentError => error
      abort "[LpAnalyticsSheetsExport] #{error.message}"
    end

    desc "Export an inclusive JST date range to the managed Google Sheets worksheet"
    task :export_range, %i[start_date end_date] => :environment do |_task, args|
      start_date = LpAnalyticsSheetsExportTask.strict_date(args[:start_date], argument_name: "start_date")
      end_date = LpAnalyticsSheetsExportTask.strict_date(args[:end_date], argument_name: "end_date")
      result = LpAnalyticsSheetsExportTask.call(start_date: start_date, end_date: end_date)
      result.lines.each { |line| puts line }
      abort "[LpAnalyticsSheetsExport] export failed" unless result.success
    rescue ArgumentError => error
      abort "[LpAnalyticsSheetsExport] #{error.message}"
    end
  end
end
