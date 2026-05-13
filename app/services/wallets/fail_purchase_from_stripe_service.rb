module Wallets
  class FailPurchaseFromStripeService
    def initialize(checkout_session:)
      @session = checkout_session
    end

    def call!
      purchase_id = @session.metadata&.[]("wallet_purchase_id").presence
      raise "missing wallet_purchase_id" if purchase_id.blank?
      purchase_id = purchase_id.to_i

      WalletPurchase.transaction do
        purchase = WalletPurchase.lock.find(purchase_id)

        return if purchase.credited?
        return if purchase.failed?

        if purchase.stripe_checkout_session_id.present? && purchase.stripe_checkout_session_id != @session.id
          raise "checkout session mismatch"
        end

        purchase.update!(
          status: :failed,
          stripe_payment_intent_id: @session.payment_intent,
          stripe_customer_id: @session.customer
        )
      end
    end
  end
end
