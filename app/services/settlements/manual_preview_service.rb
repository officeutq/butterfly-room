# frozen_string_literal: true

module Settlements
  class ManualPreviewService
    ZONE = "Asia/Tokyo"
    SHARE_RATE = BigDecimal("0.7")

    def initialize(store_id:, period_from:, period_to:)
      @store_id = store_id
      @period_from = period_from
      @period_to = period_to
    end

    def call
      gross_yen =
        StoreLedgerEntry
          .where(store_id: @store_id, occurred_at: @period_from...@period_to)
          .sum(:points)
          .to_i

      store_share_yen = (BigDecimal(gross_yen) * SHARE_RATE).floor(0).to_i
      platform_fee_yen = gross_yen - store_share_yen

      carryover_yen =
        SettlementCarryover
          .where(store_id: @store_id)
          .sum(:amount_yen)
          .to_i

      {
        period_from: @period_from,
        period_to: @period_to,
        gross_yen: gross_yen,
        store_share_yen: store_share_yen,
        platform_fee_yen: platform_fee_yen,
        carryover_yen: carryover_yen
      }
    end
  end
end
