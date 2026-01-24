# frozen_string_literal: true

module DrinkOrders
  class RefundService
    class Error < StandardError; end
    class MissingHold < Error; end
    class DuplicateHold < Error; end
    class InsufficientReserved < Error; end

    Result = Struct.new(:refunded_count, :refunded_points_sum, keyword_init: true)

    def initialize(stream_session:)
      @stream_session = stream_session
    end

    def call!
      now = Time.current

      pending_orders = DrinkOrder
        .where(stream_session_id: @stream_session.id, status: :pending)
        .lock
        .to_a

      return Result.new(refunded_count: 0, refunded_points_sum: 0) if pending_orders.empty?

      holds = WalletTransaction
        .where(kind: :hold, ref: pending_orders)
        .lock
        .to_a

      holds_by_order_id = holds.group_by(&:ref_id)

      pending_orders.each do |order|
        list = holds_by_order_id[order.id] || []
        raise MissingHold,   "hold not found drink_order_id=#{order.id}" if list.empty?
        raise DuplicateHold, "hold duplicated drink_order_id=#{order.id}" if list.size > 1
      end

      refunded_points_sum = 0

      # wallet_id ごとに集計して reserved→available を返す（顧客ごと集計の要件を満たす）
      refund_points_by_wallet_id =
        holds.group_by(&:wallet_id).transform_values { |txs| txs.sum { |tx| tx.points.abs } }

      refund_points_by_wallet_id.each do |wallet_id, points|
        refunded_points_sum += points
        wallet = Wallet.find(wallet_id)
        Wallets::ReleaseService.new(wallet: wallet, points: points).call!
      end

      # 返却ログ（注文単位で release を積む）
      pending_orders.each do |order|
        hold = holds_by_order_id.fetch(order.id).first
        price = hold.points.abs

        WalletTransaction.create!(
          wallet_id: hold.wallet_id,
          kind: :release,
          points: price,
          ref: order,
          occurred_at: now
        )
      end

      # 注文を refunded に
      DrinkOrder.where(id: pending_orders.map(&:id)).update_all(
        status: DrinkOrder.statuses.fetch("refunded"),
        refunded_at: now,
        updated_at: now
      )

      Result.new(refunded_count: pending_orders.size, refunded_points_sum: refunded_points_sum)
    end
  end
end
