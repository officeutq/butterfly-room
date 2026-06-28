# frozen_string_literal: true

module Settlements
  class MarkPaidService
    ZONE = "Asia/Tokyo"

    def initialize(settlement:, actor_user:)
      @settlement = settlement
      @actor_user = actor_user
    end

    def call
      return { ok: false, message: "exported のみ支払済みにできます" } unless @settlement.exported?

      ApplicationRecord.transaction do
        @settlement.update!(
          status: :paid,
          paid_at: Time.use_zone(ZONE) { Time.zone.now },
          paid_by_user: @actor_user
        )

        @settlement.settlement_events.create!(
          actor_user: @actor_user,
          action: :marked_paid
        )
      end

      { ok: true, settlement: @settlement }
    end
  end
end
