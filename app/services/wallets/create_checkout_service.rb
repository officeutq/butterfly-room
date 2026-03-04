module Wallets
  class CreateCheckoutService
    # 税込（= 110%）の固定プラン：Issue #292
    PLANS = {
      "p1000" => { points: 1_000, amount_jpy: 1_100 },
      "p5000" => { points: 5_000, amount_jpy: 5_500 },
      "p10000" => { points: 10_000, amount_jpy: 11_000 },
      "p50000" => { points: 50_000, amount_jpy: 55_000 },
      "p100000" => { points: 100_000, amount_jpy: 110_000 }
    }.freeze

    def initialize(customer_user:, plan_key:, booth_id:, return_to:, base_url:)
      @customer_user = customer_user
      @plan_key = plan_key
      @booth_id = booth_id
      @return_to = return_to
      @base_url = base_url
    end

    def call!
      plan = PLANS[@plan_key]
      raise ArgumentError, "invalid plan_key" if plan.blank?

      points = plan.fetch(:points)
      amount_jpy = plan.fetch(:amount_jpy)

      wallet = Wallet.find_or_create_by!(customer_user_id: @customer_user.id) do |w|
        w.available_points = 0
        w.reserved_points = 0
      end

      purchase = WalletPurchase.create!(
        wallet: wallet,
        points: points,
        booth_id: @booth_id,
        status: :pending
      )

      session = Stripe::Checkout::Session.create(
        mode: "payment",
        line_items: [
          {
            price_data: {
              currency: "jpy",
              product_data: { name: "ポイント #{points}pt" },
              unit_amount: amount_jpy
            },
            quantity: 1
          }
        ],
        success_url: build_return_url(
          status: "success",
          purchase_id: purchase.id,
          return_to: @return_to
        ),
        cancel_url: build_return_url(
          status: "cancel",
          purchase_id: purchase.id,
          return_to: @return_to
        ),
        metadata: {
          wallet_purchase_id: purchase.id,
          customer_user_id: @customer_user.id,
          plan_key: @plan_key,
          points: points,
          amount_jpy: amount_jpy
        }
      )

      purchase.update!(stripe_checkout_session_id: session.id)

      session.url
    end

    private

    def build_return_url(status:, purchase_id:, return_to:)
      path = Rails.application.routes.url_helpers.checkout_return_path(
        status: status,
        purchase_id: purchase_id,
        return_to: return_to
      )
      "#{@base_url}#{path}"
    end
  end
end
