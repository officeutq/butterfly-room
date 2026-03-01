# frozen_string_literal: true

module Admin
  class SettlementsController < Admin::BaseController
    before_action :require_current_store!
    before_action :set_settlement, only: %i[show]

    ZONE = "Asia/Tokyo"
    MIN_PAYOUT_YEN = 10_000
    SHARE_RATE = BigDecimal("0.7")

    def index
      # --- 1) estimate (this month, SSOT: StoreLedgerEntry.occurred_at) ---
      Time.use_zone(ZONE) do
        @month_from = Time.zone.today.beginning_of_month.beginning_of_day
        @month_to = Time.zone.now

        gross_yen =
          StoreLedgerEntry
            .where(store_id: current_store.id, occurred_at: @month_from...@month_to)
            .sum(:points)
            .to_i

        @month_gross_yen = gross_yen
        @month_share_yen = calc_share(gross_yen)

        @carryover_yen =
          SettlementCarryover
            .where(store_id: current_store.id)
            .sum(:amount_yen)
            .to_i

        @estimated_payable_yen = @month_share_yen + @carryover_yen
        @below_min_payout = @estimated_payable_yen < MIN_PAYOUT_YEN
      end

      # --- 2) history (store-facing: confirmed/exported/paid only) ---
      @settlements =
        current_store
          .settlements
          .where(status: %i[confirmed exported paid])
          .order(period_from: :desc, id: :desc)
    end

    def show
      # store-facing: do NOT expose payout snapshot, exports, or events
      unless %w[confirmed exported paid].include?(@settlement.status)
        head :not_found
      end
    end

    private

    def set_settlement
      @settlement = current_store.settlements.find(params[:id])
    end

    def calc_share(gross_yen)
      (BigDecimal(gross_yen) * SHARE_RATE).floor(0).to_i
    end
  end
end
