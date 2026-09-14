# frozen_string_literal: true

module DrinkOrders
  class ConsumeService
    class NotHeadError < StandardError; end
    class InvalidStatusError < StandardError; end
    class MissingWalletError < StandardError; end
    class ForbiddenError < StandardError; end
    class SessionEndedError < StandardError; end

    Result = Data.define(:drink_order, :store_ledger_entry)

    def initialize(drink_order_id:, actor:)
      @drink_order_id = drink_order_id
      @actor = actor
    end

    def call!
      drink_order = nil
      ledger_entry = nil

      ApplicationRecord.transaction do
        if StreamSessions::PublisherControl.enabled?
          target = DrinkOrder.find(@drink_order_id)
          booth = Booth.lock.find(target.booth_id)
          stream_session = StreamSession.lock.find(target.stream_session_id)
          stream_session.booth = booth
          authorize_consumption!(stream_session)
        end
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
        if StreamSessions::PublisherControl.enabled?
          comment = ConsumptionCommentService.new(drink_order: drink_order).call!
          ActiveRecord.after_all_transactions_commit do
            begin
              NotifyDrinkConsumptionJob.perform_now(comment.id)
            rescue StandardError => error
              Rails.logger.error("drink_consumption_notification_failed comment_id=#{comment.id} error=#{error.class.name}")
            end
          end
        end
      end

      return Result.new(drink_order:, store_ledger_entry: ledger_entry) if StreamSessions::PublisherControl.enabled?

      # pending一覧の置換はTX外
      DrinkOrderNotifier.replace_pending_lists(drink_order)

      # ★wallet（個人UI）は user(wallet) チャンネルで更新
      WalletNotifier.broadcast_balance_for_user(drink_order.customer_user)

      StreamSessions::Comments::CreateService.new(
        stream_session: drink_order.stream_session,
        user: drink_order.stream_session.started_by_cast_user,
        kind: Comment::KIND_DRINK_CONSUMED,
        metadata: {
          drink_item_id: drink_order.drink_item_id,
          drink_order_id: drink_order.id
        }
      ).call

      Result.new(drink_order:, store_ledger_entry: ledger_entry)
    end

    private

    def authorize_consumption!(stream_session)
      unless StreamSessions::PublisherControl.active_actor?(@actor) && stream_session.actual_publisher?(@actor) &&
          Authorization::StreamSessionPolicy.new(@actor, stream_session).publish_token?
        raise ForbiddenError
      end

      booth = stream_session.booth
      unless !booth.archived? && booth.current_stream_session_id == stream_session.id &&
          stream_session.live? && stream_session.ended_at.nil? && (booth.live? || booth.away?) &&
          stream_session.publisher_recording_state == :recorded
        raise SessionEndedError
      end
    end

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
