require "test_helper"

class Wallet::PurchasesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "customer@example.com",
      password: "password",
      role: :customer
    )
    sign_in @user, scope: :user
  end

  test "GET /wallet/purchases/new returns modal html" do
    get new_wallet_purchase_path(return_to: "/")
    assert_response :success
    assert_includes @response.body, "modal"
    assert_includes @response.body, "plan_key"
  end

  test "POST create uses plan_key and creates checkout with expected amount/points" do
    cases = {
      "p1000" => [ 1_000, 1_100 ],
      "p5000" => [ 5_000, 5_500 ],
      "p10000" => [ 10_000, 11_000 ],
      "p50000" => [ 50_000, 55_000 ],
      "p100000" => [ 100_000, 110_000 ]
    }

    cases.each do |plan_key, (points, amount_jpy)|
      called_params = nil

      fake_session =
        Struct.new(:id, :url).new(
          "cs_test_#{plan_key}",
          "https://checkout.stripe.com/pay/cs_test_#{plan_key}"
        )

      # --- create を一時的に差し替える（stub不要）---
      original = Stripe::Checkout::Session.method(:create)
      Stripe::Checkout::Session.define_singleton_method(:create) do |params|
        called_params = params
        fake_session
      end

      begin
        assert_difference "WalletPurchase.count", 1 do
          post wallet_purchases_path, params: { plan_key: plan_key, return_to: "/" }
        end
      ensure
        # 元に戻す
        Stripe::Checkout::Session.define_singleton_method(:create, original)
      end

      purchase = WalletPurchase.order(:id).last
      assert_equal points, purchase.points

      unit_amount = called_params[:line_items][0][:price_data][:unit_amount]
      assert_equal amount_jpy, unit_amount

      assert_response :redirect
      assert_equal "https://checkout.stripe.com/pay/cs_test_#{plan_key}", response.location
    end
  end

  test "POST create rejects unknown plan_key with 422" do
    post wallet_purchases_path, params: { plan_key: "bad", return_to: "/" }
    assert_response :unprocessable_entity
  end
end
