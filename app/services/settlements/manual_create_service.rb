# frozen_string_literal: true

module Settlements
  class ManualCreateService
    ZONE = "Asia/Tokyo"

    def initialize(store_id:, period_from:, period_to:, actor_user:, logger: Rails.logger)
      @store_id = store_id
      @period_from = period_from
      @period_to = period_to
      @actor_user = actor_user
      @logger = logger
    end

    def call
      # 親切エラー（事前チェック）
      existing =
        Settlement
          .where(store_id: @store_id)
          .where("tsrange(period_from, period_to) && tsrange(?, ?)", @period_from, @period_to)
          .order(period_from: :asc)
          .first

      if existing.present?
        from_str = existing.period_from.in_time_zone(ZONE).strftime("%Y-%m-%d %H:%M")
        to_str   = existing.period_to.in_time_zone(ZONE).strftime("%Y-%m-%d %H:%M")
        return { ok: false, message: "この期間は既に精算済みです（#{from_str}..#{to_str}）" }
      end

      preview =
        ManualPreviewService.new(
          store_id: @store_id,
          period_from: @period_from,
          period_to: @period_to
        ).call

      settlement =
        Settlement.create!(
          store_id: @store_id,
          kind: :manual,
          status: :confirmed,
          confirmed_at: Time.use_zone(ZONE) { Time.zone.now },
          period_from: @period_from,
          period_to: @period_to,
          gross_yen: preview[:gross_yen],
          store_share_yen: preview[:store_share_yen],
          platform_fee_yen: preview[:platform_fee_yen]
        )

      @logger.info(
        "[ManualSettlement] created user_id=#{@actor_user.id} store_id=#{@store_id} " \
        "period=#{@period_from}..#{@period_to} gross=#{preview[:gross_yen]} " \
        "share=#{preview[:store_share_yen]} fee=#{preview[:platform_fee_yen]}"
      )

      { ok: true, settlement: settlement }
    rescue ActiveRecord::RecordNotUnique
      { ok: false, message: "この期間は既に精算済みです（同一期間の精算が存在します）" }
    rescue ActiveRecord::StatementInvalid => e
      # EXCLUDE制約 (PG::ExclusionViolation) など
      if e.cause&.class&.name.to_s.include?("ExclusionViolation")
        { ok: false, message: "この期間は既に精算済みです（期間が重複しています）" }
      else
        raise
      end
    end
  end
end
