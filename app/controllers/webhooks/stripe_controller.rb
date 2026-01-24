class Webhooks::StripeController < ActionController::Base
  protect_from_forgery with: :null_session

  def create
    payload = request.raw_post
    sig = request.env["HTTP_STRIPE_SIGNATURE"]

    secret =
      ENV["STRIPE_WEBHOOK_SECRET"].presence ||
      Rails.application.credentials.dig(:stripe, :webhook_secret)

    raise "Stripe webhook secret is missing" if secret.blank?

    event = Stripe::Webhook.construct_event(payload, sig, secret)

    # 冪等：同じ event_id は2回処理しない
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
  rescue ActiveRecord::RecordNotUnique
    # 同一イベント再送：正常系として 200 を返す
    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  end
end
