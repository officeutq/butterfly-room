module Wallets
  class ApplyPurchaseFromStripeService
    def initialize(checkout_session:)
      @session = checkout_session
    end

    def call!
      ensure_paid_session!

      purchase_id = @session.metadata&.[]("wallet_purchase_id").presence
      raise "missing wallet_purchase_id" if purchase_id.blank?
      purchase_id = purchase_id.to_i

      credited_wallet_id = nil
      credited_user_id = nil

      WalletPurchase.transaction do
        purchase = WalletPurchase.lock.find(purchase_id)
        return if purchase.credited? # 冪等（最低限）

        if purchase.stripe_checkout_session_id.present? && purchase.stripe_checkout_session_id != @session.id
          raise "checkout session mismatch"
        end

        purchase.update!(
          status: :paid,
          stripe_payment_intent_id: @session.payment_intent,
          stripe_customer_id: @session.customer,
          paid_at: Time.current
        )

        wallet = Wallet.lock.find(purchase.wallet_id)
        wallet.update!(available_points: wallet.available_points + purchase.points)

        WalletTransaction.create!(
          wallet: wallet,
          kind: :purchase,
          points: purchase.points,
          ref: purchase,
          occurred_at: Time.current
        )

        purchase.update!(status: :credited, credited_at: Time.current)

        credited_wallet_id = wallet.id
        credited_user_id = wallet.customer_user_id
      end

      # ★購入反映後に個人チャンネルで更新（TX外）
      if credited_wallet_id && credited_user_id
        user = User.find_by(id: credited_user_id)
        WalletNotifier.broadcast_balance_for_user(user) if user
      end
    end

    private

    def ensure_paid_session!
      return if @session.payment_status == "paid"

      raise "checkout session is not paid. session_id=#{@session.id} payment_status=#{@session.payment_status}"
    end
  end
end
