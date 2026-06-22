# frozen_string_literal: true

require "test_helper"

class DrinkOrders::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "drink-order-create-service")
    @cast = User.create!(email: "drink_order_create_cast@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "drink_order_create_customer@example.com", password: "password", role: :customer)
    @admin = User.create!(email: "drink_order_create_admin@example.com", password: "password", role: :store_admin)
    @booth = Booth.create!(store: @store, name: "Booth", status: :live)
    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/drink-order-create"
    )
    @booth.update!(current_stream_session: @stream_session)
    @drink_item = DrinkItem.create!(store: @store, name: "drink", price_points: 100, enabled: true)
    Wallet.create!(customer_user: @customer, available_points: 1_000, reserved_points: 0)
  end

  test "banned customer cannot create drink order at service layer" do
    StoreBan.create!(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)

    assert_no_difference "DrinkOrder.count" do
      assert_raises(DrinkOrders::CreateService::Forbidden) do
        DrinkOrders::CreateService.new(
          stream_session: @stream_session,
          customer_user: @customer,
          drink_item: @drink_item
        ).call!
      end
    end
  end

  test "revoked ban does not block drink order creation" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      revoked_at: Time.current,
      revoked_by_user: @admin
    )

    assert_difference "DrinkOrder.count", 1 do
      DrinkOrders::CreateService.new(
        stream_session: @stream_session,
        customer_user: @customer,
        drink_item: @drink_item
      ).call!
    end
  end
end
