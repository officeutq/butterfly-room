# frozen_string_literal: true

module Settlements
  class MonthlyGenerateService
    ZONE = "Asia/Tokyo"
    MIN_PAYOUT_YEN = 10_000
    SHARE_RATE = BigDecimal("0.7")

    Result = Data.define(:created_count, :skipped)

    # skipped: [{ store_id:, reason:, detail: }, ...]
    def initialize(target_month: nil, logger: Rails.logger)
      @target_month = target_month
      @logger = logger
    end

    def call
      period_from, period_to = MonthPeriod.for_previous_month(target_month: @target_month)

      created = 0
      skipped = []

      # store別にgrossを集計（occurred_atがSSOT）
      gross_by_store =
        StoreLedgerEntry
          .where(occurred_at: period_from...period_to)
          .group(:store_id)
          .sum(:points) # 1pt = 1円

      if gross_by_store.empty?
        @logger.info("[MonthlySettlement] no data period=#{period_from}..#{period_to}")
        return Result.new(created_count: 0, skipped: [])
      end

      gross_by_store.each do |store_id, gross_yen|
        gross_yen = gross_yen.to_i
        if gross_yen <= 0
          skipped << { store_id: store_id, reason: "no_data", detail: "gross=0" }
          next
        end

        # settlement冪等（store+periodが既に存在）
        if Settlement.exists?(store_id: store_id, period_from: period_from, period_to: period_to)
          skipped << { store_id: store_id, reason: "already_exists", detail: "settlement exists" }
          next
        end

        # 1万円未満で settlement を作らない月も、二重実行で結果が変わらないようにガード
        if SettlementCarryover.exists?(
            store_id: store_id,
            reason: :min_payout_carryover,
            period_from: period_from,
            period_to: period_to
          )
          skipped << { store_id: store_id, reason: "already_processed_below_min_payout", detail: "carryover already added for this period" }
          next
        end

        month_share_yen = calc_store_share(gross_yen)
        platform_fee_yen = gross_yen - month_share_yen

        carryover_yen =
          SettlementCarryover
            .where(store_id: store_id)
            .sum(:amount_yen)
            .to_i

        payable_yen = month_share_yen + carryover_yen

        if payable_yen < MIN_PAYOUT_YEN
          # settlement作らず繰越へ（同月二重加算は unique index で防ぐ）
          begin
            SettlementCarryover.create!(
              store_id: store_id,
              amount_yen: month_share_yen,
              reason: :min_payout_carryover,
              period_from: period_from,
              period_to: period_to,
              created_at: Time.use_zone(ZONE) { Time.zone.now }
            )
            skipped << { store_id: store_id, reason: "below_min_payout", detail: "payable=#{payable_yen}" }
          rescue ActiveRecord::RecordNotUnique
            # 二重実行で既に積まれている
            skipped << { store_id: store_id, reason: "below_min_payout_already_added", detail: "carryover already added" }
          end
          next
        end

        # payable >= 10_000 → settlement作成 + carryover全消し
        begin
          ApplicationRecord.transaction do
            settlement = Settlement.create!(
              store_id: store_id,
              kind: :monthly,
              status: :draft,
              period_from: period_from,
              period_to: period_to,
              gross_yen: gross_yen,
              # store_share_yenは「今月分 + 繰越」を入れる（仕様固定）
              store_share_yen: payable_yen,
              # 手数料は今月grossにのみ掛かる（繰越は手数料対象外）
              platform_fee_yen: platform_fee_yen
            )

            if carryover_yen != 0
              SettlementCarryover.create!(
                store_id: store_id,
                amount_yen: -carryover_yen,
                reason: :applied_to_settlement,
                applied_settlement: settlement,
                created_at: Time.use_zone(ZONE) { Time.zone.now }
              )
            end

            created += 1
          end
        rescue ActiveRecord::RecordNotUnique
          # settlementのuniq衝突＝既存扱い
          skipped << { store_id: store_id, reason: "already_exists_race", detail: "unique conflict" }
          next
        end
      end

      Result.new(created_count: created, skipped: skipped)
    end

    private

    def calc_store_share(gross_yen)
      (BigDecimal(gross_yen) * SHARE_RATE).floor(0).to_i
    end
  end
end
