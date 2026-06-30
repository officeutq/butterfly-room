# frozen_string_literal: true

module Admin
  class SalesController < Admin::BaseController
    before_action :require_current_store!

    ZONE = "Asia/Tokyo"

    def index
      @selected_month = selected_month_param
      @period_from, @period_to = month_period(@selected_month)
      @report =
        AdminSalesReportQuery.new(
          store: current_store,
          from: @period_from,
          to: @period_to
        ).call
    end

    private

    def selected_month_param
      month = params[:month].to_s.strip
      return default_month if month.blank?
      return month if valid_month?(month)

      default_month
    end

    def valid_month?(month)
      return false unless /\A\d{4}-\d{2}\z/.match?(month)

      Date.strptime("#{month}-01", "%Y-%m-%d")
      true
    rescue Date::Error
      false
    end

    def default_month
      Time.use_zone(ZONE) { Time.zone.today.strftime("%Y-%m") }
    end

    def month_period(month)
      Time.use_zone(ZONE) do
        date = Date.strptime("#{month}-01", "%Y-%m-%d")
        period_from = Time.zone.local(date.year, date.month, 1).beginning_of_day
        period_to = period_from.next_month

        [ period_from, period_to ]
      end
    end
  end
end
