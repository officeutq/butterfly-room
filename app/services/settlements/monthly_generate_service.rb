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

      gross_by_store.each do |store_id, _gross_yen_whole_month|
        begin
          created_for_store = process_store!(store_id: store_id, month_from: period_from, month_to: period_to, skipped: skipped)
          created += created_for_store
        rescue ActiveRecord::RecordNotUnique
          skipped << { store_id: store_id, reason: "already_exists_race", detail: "unique conflict" }
          next
        rescue ActiveRecord::StatementInvalid => e
          # EXCLUDE制約 (PG::ExclusionViolation) など
          if e.cause&.class&.name.to_s.include?("ExclusionViolation")
            skipped << { store_id: store_id, reason: "already_exists_race", detail: "exclusion conflict" }
            next
          end
          raise
        end
      end

      Result.new(created_count: created, skipped: skipped)
    end

    private

    def process_store!(store_id:, month_from:, month_to:, skipped:)
      # 既存settlement（manual/monthly問わず）で月次対象期間とoverlapするものを除外対象とする
      existing_ranges = fetch_existing_ranges(store_id: store_id, month_from: month_from, month_to: month_to)

      gaps = subtract_ranges(month_from, month_to, existing_ranges)
      if gaps.empty?
        skipped << { store_id: store_id, reason: "no_unsettled_ranges", detail: "covered by existing settlements" }
        return 0
      end

      # 各gapごとの集計（gross/share/fee）
      segments = gaps.map do |from, to|
        gross_yen =
          StoreLedgerEntry
            .where(store_id: store_id, occurred_at: from...to)
            .sum(:points)
            .to_i

        share_yen = calc_store_share(gross_yen)
        fee_yen = gross_yen - share_yen

        { from: from, to: to, gross_yen: gross_yen, share_yen: share_yen, fee_yen: fee_yen }
      end

      sum_share_yen = segments.sum { |s| s[:share_yen].to_i }

      # 1万円未満で settlement を作らない月も、二重実行で結果が変わらないようにガード
      if SettlementCarryover.exists?(
          store_id: store_id,
          reason: :min_payout_carryover,
          period_from: month_from,
          period_to: month_to
        )
        skipped << { store_id: store_id, reason: "already_processed_below_min_payout", detail: "carryover already added for this period" }
        return 0
      end

      carryover_yen =
        SettlementCarryover
          .where(store_id: store_id)
          .sum(:amount_yen)
          .to_i

      payable_total = sum_share_yen + carryover_yen

      if payable_total < MIN_PAYOUT_YEN
        # settlement作らず繰越へ（同月二重加算は unique index で防ぐ）
        begin
          SettlementCarryover.create!(
            store_id: store_id,
            amount_yen: sum_share_yen,
            reason: :min_payout_carryover,
            period_from: month_from,
            period_to: month_to,
            created_at: Time.use_zone(ZONE) { Time.zone.now }
          )
          skipped << { store_id: store_id, reason: "below_min_payout", detail: "payable_total=#{payable_total}" }
        rescue ActiveRecord::RecordNotUnique
          skipped << { store_id: store_id, reason: "below_min_payout_already_added", detail: "carryover already added" }
        end
        return 0
      end

      # payable_total >= 10_000 → gapごとに settlement作成 + carryoverは最初の1件だけ加算し相殺
      created_count = 0

      ApplicationRecord.transaction do
        first_settlement = nil

        segments.each_with_index do |seg, idx|
          store_share_yen = seg[:share_yen]
          store_share_yen += carryover_yen if idx == 0

          settlement = Settlement.create!(
            store_id: store_id,
            kind: :monthly,
            status: :draft,
            period_from: seg[:from],
            period_to: seg[:to],
            gross_yen: seg[:gross_yen],
            store_share_yen: store_share_yen,
            platform_fee_yen: seg[:fee_yen]
          )

          first_settlement ||= settlement
          created_count += 1
        end

        if carryover_yen != 0 && first_settlement.present?
          SettlementCarryover.create!(
            store_id: store_id,
            amount_yen: -carryover_yen,
            reason: :applied_to_settlement,
            applied_settlement: first_settlement,
            created_at: Time.use_zone(ZONE) { Time.zone.now }
          )
        end
      end

      created_count
    end

    def fetch_existing_ranges(store_id:, month_from:, month_to:)
      rows =
        Settlement
          .where(store_id: store_id)
          .where("tsrange(period_from, period_to) && tsrange(?, ?)", month_from, month_to)
          .order(period_from: :asc, period_to: :asc)
          .pluck(:period_from, :period_to)

      clamped =
        rows.map do |from, to|
          f = [ from, month_from ].max
          t = [ to, month_to ].min
          next nil unless f < t
          [ f, t ]
        end.compact

      merge_ranges(clamped)
    end

    def merge_ranges(ranges)
      return [] if ranges.empty?

      sorted = ranges.sort_by { |from, to| [ from, to ] }
      merged = []
      cur_from, cur_to = sorted.first

      sorted.drop(1).each do |from, to|
        if from <= cur_to
          cur_to = [ cur_to, to ].max
        else
          merged << [ cur_from, cur_to ]
          cur_from = from
          cur_to = to
        end
      end

      merged << [ cur_from, cur_to ]
      merged
    end

    def subtract_ranges(base_from, base_to, covered_ranges)
      gaps = []
      cursor = base_from

      covered_ranges.each do |from, to|
        next if to <= cursor
        if cursor < from
          gaps << [ cursor, from ]
        end
        cursor = [ cursor, to ].max
        break if cursor >= base_to
      end

      gaps << [ cursor, base_to ] if cursor < base_to
      gaps
    end

    def calc_store_share(gross_yen)
      (BigDecimal(gross_yen) * SHARE_RATE).floor(0).to_i
    end
  end
end
