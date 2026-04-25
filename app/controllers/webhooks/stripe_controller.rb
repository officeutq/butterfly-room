class Webhooks::StripeController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  def create
    payload = request.raw_post
    sig     = request.env["HTTP_STRIPE_SIGNATURE"]

    secret =
      ENV["STRIPE_WEBHOOK_SECRET"].presence ||
      Rails.application.credentials.dig(:stripe, :webhook_secret)

    raise "Stripe webhook secret is missing" if secret.blank?

    event = Stripe::Webhook.construct_event(payload, sig, secret)

    # 先に「受け取った」ことを記録（冪等キー）
    StripeWebhookEvent.create!(
      event_id: event.id,
      event_type: event.type,
      received_at: Time.current
    )

    case event.type
    when "checkout.session.completed"
      session = event.data.object
      purchase_id = session.metadata&.[]("wallet_purchase_id").presence

      if purchase_id.blank?
        Rails.logger.warn("[stripe] checkout.session.completed missing wallet_purchase_id. session_id=#{session.id}")
        return head :ok
      end

      Wallets::ApplyPurchaseFromStripeService.new(checkout_session: session).call!
    end

    head :ok
  rescue ActiveRecord::RecordNotUnique
    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  end
end
