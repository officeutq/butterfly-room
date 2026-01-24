module Wallets
  class CreateCheckoutService
    PACK_POINTS = [ 1000, 3000, 5000 ].freeze

    def initialize(customer_user:, points:, booth_id:, base_url:)
      @customer_user = customer_user
      @points = points
      @booth_id = booth_id
      @base_url = base_url
    end

    def call!
      raise ArgumentError, "invalid points" unless PACK_POINTS.include?(@points)

      wallet = Wallet.find_or_create_by!(customer_user_id: @customer_user.id) do |w|
        w.available_points = 0
        w.reserved_points = 0
      end

      purchase = WalletPurchase.create!(
        wallet: wallet,
        points: @points,
        booth_id: @booth_id,
        status: :pending
      )

      session = Stripe::Checkout::Session.create(
        mode: "payment",
        line_items: [
          {
            price_data: {
              currency: "jpy",
              product_data: { name: "ポイント #{@points}pt" },
              unit_amount: @points
            },
            quantity: 1
          }
        ],
        success_url: build_return_url(status: "success", purchase_id: purchase.id, booth_id: @booth_id),
        cancel_url:  build_return_url(status: "cancel",  purchase_id: purchase.id, booth_id: @booth_id),
        metadata: {
          wallet_purchase_id: purchase.id,
          customer_user_id: @customer_user.id
        }
      )

      purchase.update!(stripe_checkout_session_id: session.id)

      session.url
    end

    private

    def build_return_url(status:, purchase_id:, booth_id:)
      path = Rails.application.routes.url_helpers.checkout_return_path(
        status: status,
        purchase_id: purchase_id,
        booth_id: booth_id
      )
      "#{@base_url}#{path}"
    end
  end
end
