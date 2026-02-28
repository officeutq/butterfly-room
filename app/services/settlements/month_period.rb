# frozen_string_literal: true

module Settlements
  class MonthPeriod
    ZONE = "Asia/Tokyo"

    # target_month: Date / Time / String("2026-03") / nil
    def self.for_previous_month(target_month: nil)
      Time.use_zone(ZONE) do
        month_start =
          if target_month.nil?
            Time.zone.today.prev_month.beginning_of_month
          else
            parse_to_date(target_month).beginning_of_month
          end

        from = month_start.in_time_zone.beginning_of_day
        to   = (month_start.next_month).in_time_zone.beginning_of_day
        [ from, to ]
      end
    end

    def self.parse_to_date(value)
      return value.to_date if value.respond_to?(:to_date)

      str = value.to_s.strip
      # "YYYY-MM" を許可
      if /\A\d{4}-\d{2}\z/.match?(str)
        Date.strptime("#{str}-01", "%Y-%m-%d")
      else
        Date.parse(str)
      end
    end
    private_class_method :parse_to_date
  end
end
