# frozen_string_literal: true

module Admin
  class MetricsController < Admin::BaseController
    before_action :require_current_store!

    ZONE = "Asia/Tokyo"

    def cast
      @selected_month = selected_month_param
      @include_all_casts = params[:all_casts].present?

      @period_from, @period_to =
        Settlements::MonthPeriod.for_previous_month(target_month: @selected_month)

      @month_options = month_options

      @rows =
        CastMetricsQuery.new(
          store: current_store,
          from: @period_from,
          to: @period_to,
          include_all_casts: @include_all_casts
        ).call
    end

    private

    def selected_month_param
      month = params[:month].to_s.strip
      return default_month if month.blank?
      return month if /\A\d{4}-\d{2}\z/.match?(month)

      default_month
    end

    def default_month
      Time.use_zone(ZONE) { Time.zone.today.prev_month.strftime("%Y-%m") }
    end

    def month_options
      Time.use_zone(ZONE) do
        start_month = metrics_start_month
        end_month = Time.zone.today.beginning_of_month

        months = []
        cursor = end_month

        while cursor >= start_month
          months << [ cursor.strftime("%Y年%-m月"), cursor.strftime("%Y-%m") ]
          cursor = cursor.prev_month
        end

        months
      end
    end

    def metrics_start_month
      first_ledger_at =
        StoreLedgerEntry
          .where(store_id: current_store.id)
          .minimum(:occurred_at)

      first_session_at =
        StreamSession
          .where(store_id: current_store.id)
          .where.not(broadcast_started_at: nil)
          .minimum(:broadcast_started_at)

      first_at = [ first_ledger_at, first_session_at ].compact.min

      Time.use_zone(ZONE) do
        (first_at || Time.zone.today.prev_month).to_date.beginning_of_month
      end
    end
  end
end
