require "test_helper"
require "ostruct"

class Webhooks::StripeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "stripe-test@example.com",
      password: "password",
      role: :customer
    )

    @wallet = Wallet.create!(
      customer_user: @user,
      available_points: 0,
      reserved_points: 0
    )

    @purchase = WalletPurchase.create!(
      wallet: @wallet,
      points: 1000,
      status: :pending,
      stripe_checkout_session_id: "cs_test_123"
    )

    @headers = { "Stripe-Signature" => "test_signature" }
  end

  test "checkout.session.completed with paid credits wallet" do
    event = stripe_event(
      type: "checkout.session.completed",
      payment_status: "paid"
    )

    with_stubbed_stripe_event(event) do
      assert_difference -> { WalletTransaction.count }, 1 do
        post webhooks_stripe_path, params: "{}", headers: @headers
      end
    end

    assert_response :success
    assert_equal 1000, @wallet.reload.available_points
    assert @purchase.reload.credited?
  end

  test "checkout.session.completed with unpaid does not credit wallet" do
    event = stripe_event(
      type: "checkout.session.completed",
      payment_status: "unpaid"
    )

    with_stubbed_stripe_event(event) do
      assert_no_difference -> { WalletTransaction.count } do
        post webhooks_stripe_path, params: "{}", headers: @headers
      end
    end

    assert_response :success
    assert_equal 0, @wallet.reload.available_points
    assert @purchase.reload.pending?
  end

  test "checkout.session.async_payment_succeeded credits wallet" do
    event = stripe_event(
      type: "checkout.session.async_payment_succeeded",
      payment_status: "paid"
    )

    with_stubbed_stripe_event(event) do
      assert_difference -> { WalletTransaction.count }, 1 do
        post webhooks_stripe_path, params: "{}", headers: @headers
      end
    end

    assert_response :success
    assert_equal 1000, @wallet.reload.available_points
    assert @purchase.reload.credited?
  end

  test "checkout.session.async_payment_failed marks purchase as failed" do
    event = stripe_event(
      type: "checkout.session.async_payment_failed",
      payment_status: "unpaid"
    )

    with_stubbed_stripe_event(event) do
      assert_no_difference -> { WalletTransaction.count } do
        post webhooks_stripe_path, params: "{}", headers: @headers
      end
    end

    assert_response :success
    assert_equal 0, @wallet.reload.available_points
    assert @purchase.reload.failed?
  end

  private

  def stripe_event(type:, payment_status:)
    session =
      OpenStruct.new(
        id: "cs_test_123",
        payment_status: payment_status,
        payment_intent: "pi_test_123",
        customer: "cus_test_123",
        metadata: {
          "wallet_purchase_id" => @purchase.id.to_s
        }
      )

    OpenStruct.new(
      id: "evt_#{SecureRandom.hex(8)}",
      type: type,
      data: OpenStruct.new(object: session)
    )
  end

  def with_stubbed_stripe_event(event)
    original_method = Stripe::Webhook.method(:construct_event)

    Stripe::Webhook.singleton_class.send(
      :define_method,
      :construct_event
    ) do |*_args|
      event
    end

    yield
  ensure
    Stripe::Webhook.singleton_class.send(
      :define_method,
      :construct_event,
      original_method
    )
  end
end
