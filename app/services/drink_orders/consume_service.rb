# frozen_string_literal: true

module DrinkOrders
  class ConsumeService
    class NotHeadError < StandardError; end
    class InvalidStatusError < StandardError; end
    class MissingWalletError < StandardError; end

    Result = Data.define(:drink_order, :store_ledger_entry)

    def initialize(drink_order_id:)
      @drink_order_id = drink_order_id
    end

    def call!
      drink_order = nil
      ledger_entry = nil

      ApplicationRecord.transaction do
        # 対象注文をロック
        drink_order = DrinkOrder.lock.find(@drink_order_id)
        raise InvalidStatusError unless drink_order.pending?

        # FIFO先頭pendingをロックして取得
        head = DrinkOrders::FifoGuard
          .new(stream_session_id: drink_order.stream_session_id)
          .lock_head_pending!

        raise NotHeadError if head.nil? || head.id != drink_order.id

        now = Time.current
        points = hold_points_for!(drink_order)

        # reserved 減 + consume transaction 記録
        wallet = drink_order.customer_user.wallet
        raise MissingWalletError if wallet.nil? # #19前提なら基本起きないが保険

        Wallets::ConsumeService.new(
          wallet: wallet,
          points: points,
          ref: drink_order,
          occurred_at: now
        ).call!

        # consumed確定（売上確定の基準時刻もこれ）
        drink_order.update!(status: :consumed, consumed_at: now)

        # 店舗売上台帳へ計上（冪等：unique drink_order_id）
        ledger_entry = create_ledger_entry!(drink_order:, points:, occurred_at: now)
      end

      # pending一覧の置換はTX外
      DrinkOrderNotifier.replace_pending_lists(drink_order)

      Result.new(drink_order:, store_ledger_entry: ledger_entry)
    end

    private

    def create_ledger_entry!(drink_order:, points:, occurred_at:)
      StoreLedgerEntry.create!(
        store_id: drink_order.store_id,
        stream_session_id: drink_order.stream_session_id,
        drink_order_id: drink_order.id,
        points: points,
        occurred_at: occurred_at
      )
    rescue ActiveRecord::RecordNotUnique
      StoreLedgerEntry.find_by!(drink_order_id: drink_order.id)
    end

    def hold_points_for!(drink_order)
      txs = WalletTransaction.where(kind: :hold, ref: drink_order).lock.to_a
      raise MissingWalletError, "hold tx missing drink_order_id=#{drink_order.id}" if txs.empty?
      raise MissingWalletError, "hold tx duplicated drink_order_id=#{drink_order.id}" if txs.size > 1
      txs.first.points.abs
    end
  end
end
