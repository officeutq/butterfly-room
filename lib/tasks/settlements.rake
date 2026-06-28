# frozen_string_literal: true

module SettlementMonthlyGenerateTask
  MONTH_FORMAT = /\A\d{4}-\d{2}\z/
  CARRYOVER_REASONS = %w[below_min_payout].freeze

  module_function

  def call(target_month_arg)
    target_month = normalize_target_month(target_month_arg)
    period_from, period_to = Settlements::MonthPeriod.for_previous_month(target_month: target_month)

    result = Settlements::MonthlyGenerateService.new(target_month: target_month).call
    carryover_count = carryover_count(result)
    skipped_count = result.skipped.size - carryover_count

    [
      summary_line(
        period_from: period_from,
        period_to: period_to,
        created_count: result.created_count,
        carryover_count: carryover_count,
        skipped_count: skipped_count
      ),
      *detail_lines(result)
    ]
  end

  def normalize_target_month(value)
    target_month = value.to_s.strip
    return nil if target_month.empty?

    unless MONTH_FORMAT.match?(target_month)
      raise ArgumentError, "invalid target_month=#{target_month.inspect}; expected YYYY-MM"
    end

    Date.strptime("#{target_month}-01", "%Y-%m-%d")
    target_month
  rescue Date::Error
    raise ArgumentError, "invalid target_month=#{target_month.inspect}; expected YYYY-MM"
  end

  def summary_line(period_from:, period_to:, created_count:, carryover_count:, skipped_count:)
    "[MonthlySettlement] target=#{period_from.to_date}..#{period_to.to_date} " \
      "created=#{created_count} carryover=#{carryover_count} skipped=#{skipped_count}"
  end

  def detail_lines(result)
    result.skipped.map do |item|
      classification = carryover_reason?(item[:reason]) ? "carryover_detail" : "skipped_detail"
      "[MonthlySettlement] #{classification} store_id=#{item[:store_id]} " \
        "reason=#{item[:reason]} detail=#{item[:detail]}"
    end
  end

  def carryover_count(result)
    result.skipped.count { |item| carryover_reason?(item[:reason]) }
  end

  def carryover_reason?(reason)
    CARRYOVER_REASONS.include?(reason.to_s)
  end
end

namespace :settlements do
  desc "Generate monthly settlements for the previous JST month or specified YYYY-MM"
  task :monthly_generate, [ :target_month ] => :environment do |_task, args|
    SettlementMonthlyGenerateTask.call(args[:target_month]).each do |line|
      puts line
    end
  rescue ArgumentError => e
    abort "[MonthlySettlement] #{e.message}"
  end
end
