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

      # booth 状態（live/awayだけOK）
      unless booth.status.in?(%w[live away])
        raise Conflict
      end

      # BAN
      if StoreBan.exists?(store_id: booth.store_id, customer_user_id: @customer_user.id)
        raise Forbidden
      end

      # item 妥当性
      unless @drink_item.store_id == booth.store_id && @drink_item.enabled? && @drink_item.price_points.to_i.positive?
        raise InvalidItem
      end

      wallet = Wallet.find_by!(customer_user_id: @customer_user.id)
      price  = @drink_item.price_points

      drink_order = nil

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
      end

      # commit後に通知（ロールバック時の誤通知防止）
      DrinkOrderNotifier.replace_pending_lists(drink_order)

      Result.new(drink_order: drink_order, wallet: wallet.reload)
    end
  end
end
