module Wallets
  class ApplyPurchaseFromStripeService
    def initialize(checkout_session:)
      @session = checkout_session
    end

    def call!
      purchase_id = @session.metadata&.[]("wallet_purchase_id").presence
      raise "missing wallet_purchase_id" if purchase_id.blank?
      purchase_id = purchase_id.to_i

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
      end
    end
  end
end
