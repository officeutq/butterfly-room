# frozen_string_literal: true

module DrinkOrders
  class CreateService
    class Forbidden < StandardError; end
    class Conflict < StandardError; end
    class InvalidItem < StandardError; end

    Result = Struct.new(:drink_order, :wallet, keyword_init: true)

    def initialize(stream_session:, customer_user:, drink_item:)
      @stream_session = stream_session
      @customer_user  = customer_user
      @drink_item     = drink_item
    end

    def call!
      booth = @stream_session.booth

      unless booth.status.in?(%w[live away])
        raise Conflict
      end

      unless @drink_item.store_id == booth.store_id && @drink_item.enabled? && @drink_item.price_points.to_i.positive?
        raise InvalidItem
      end

      wallet = Wallet.find_by!(customer_user_id: @customer_user.id)
      price  = @drink_item.price_points

      drink_order = nil
      comment = nil

      ApplicationRecord.transaction do
        Wallets::HoldService.new(wallet: wallet, points: price).call!

        drink_order = DrinkOrder.create!(
          store_id: booth.store_id,
          booth_id: booth.id,
          stream_session_id: @stream_session.id,
          customer_user_id: @customer_user.id,
          drink_item_id: @drink_item.id,
          status: :pending
        )

        WalletTransaction.create!(
          wallet_id: wallet.id,
          kind: :hold,
          points: -price,
          ref: drink_order,
          occurred_at: Time.current
        )

        comment = StreamSessions::Comments::CreateService.new(
          stream_session: @stream_session,
          user: @customer_user,
          kind: Comment::KIND_DRINK,
          metadata: {
            drink_item_id: @drink_item.id,
            drink_order_id: drink_order.id
          },
          notify: false
        ).call
      end

      DrinkOrderNotifier.replace_pending_lists(drink_order)
      WalletNotifier.broadcast_balance_for_user(@customer_user)
      CommentNotifier.append(comment)

      Result.new(drink_order: drink_order, wallet: wallet.reload)
    end
  end
end
