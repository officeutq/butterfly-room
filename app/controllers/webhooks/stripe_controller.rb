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
      handle_checkout_session_completed(event.data.object)
    when "checkout.session.async_payment_succeeded"
      handle_checkout_session_async_payment_succeeded(event.data.object)
    when "checkout.session.async_payment_failed"
      handle_checkout_session_async_payment_failed(event.data.object)
    end

    head :ok
  rescue ActiveRecord::RecordNotUnique
    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  end

  private

  def handle_checkout_session_completed(session)
    unless wallet_purchase_id_present?(session)
      Rails.logger.warn("[stripe] checkout.session.completed missing wallet_purchase_id. session_id=#{session.id}")
      return
    end

    if session.payment_status == "paid"
      Wallets::ApplyPurchaseFromStripeService.new(checkout_session: session).call!
      return
    end

    Rails.logger.info(
      "[stripe] checkout.session.completed without paid status. " \
      "session_id=#{session.id} payment_status=#{session.payment_status}"
    )
  end

  def handle_checkout_session_async_payment_succeeded(session)
    unless wallet_purchase_id_present?(session)
      Rails.logger.warn("[stripe] checkout.session.async_payment_succeeded missing wallet_purchase_id. session_id=#{session.id}")
      return
    end

    Wallets::ApplyPurchaseFromStripeService.new(checkout_session: session).call!
  end

  def handle_checkout_session_async_payment_failed(session)
    unless wallet_purchase_id_present?(session)
      Rails.logger.warn("[stripe] checkout.session.async_payment_failed missing wallet_purchase_id. session_id=#{session.id}")
      return
    end

    Wallets::FailPurchaseFromStripeService.new(checkout_session: session).call!
  end

  def wallet_purchase_id_present?(session)
    session.metadata&.[]("wallet_purchase_id").present?
  end
end
