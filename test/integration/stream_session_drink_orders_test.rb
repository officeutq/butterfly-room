# frozen_string_literal: true

require "test_helper"

class StreamSessionDrinkOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store-drink-orders")
    @booth = Booth.create!(
      store: @store,
      name: "booth-drink-orders",
      status: :live,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/test-stage"
    )

    @stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      started_by_cast_user: create_user!("started-by-cast@example.com", :cast),
      started_at: Time.current,
      status: :live,
      ivs_stage_arn: @booth.ivs_stage_arn
    )

    @booth.update!(current_stream_session_id: @stream_session.id)

    @drink_item = DrinkItem.create!(
      store: @store,
      name: "テストドリンク",
      price_points: 100,
      enabled: true
    )
  end

  test "customer can create drink order" do
    user = create_user!("customer@example.com", :customer)
    create_wallet!(user, 1_000)

    sign_in user

    assert_difference("DrinkOrder.count", 1) do
      post stream_session_drink_orders_path(@stream_session), params: {
        drink_order: { drink_item_id: @drink_item.id }
      }
    end

    assert_redirected_to booth_path(@booth)

    drink_order = DrinkOrder.order(:id).last
    assert_equal user.id, drink_order.customer_user_id
    assert_equal @stream_session.id, drink_order.stream_session_id
    assert_equal @drink_item.id, drink_order.drink_item_id
  end

  test "cast can create drink order without forbidden" do
    user = create_user!("cast@example.com", :cast)
    create_wallet!(user, 1_000)

    sign_in user

    assert_difference("DrinkOrder.count", 1) do
      post stream_session_drink_orders_path(@stream_session), params: {
        drink_order: { drink_item_id: @drink_item.id }
      }
    end

    assert_response :redirect
    assert_not_equal 403, response.status
  end

  test "store_admin can create drink order without forbidden" do
    user = create_user!("store-admin@example.com", :store_admin)
    create_wallet!(user, 1_000)

    sign_in user

    assert_difference("DrinkOrder.count", 1) do
      post stream_session_drink_orders_path(@stream_session), params: {
        drink_order: { drink_item_id: @drink_item.id }
      }
    end

    assert_response :redirect
    assert_not_equal 403, response.status
  end

  test "system_admin can create drink order without forbidden" do
    user = create_user!("system-admin@example.com", :system_admin)
    create_wallet!(user, 1_000)

    sign_in user

    assert_difference("DrinkOrder.count", 1) do
      post stream_session_drink_orders_path(@stream_session), params: {
        drink_order: { drink_item_id: @drink_item.id }
      }
    end

    assert_response :redirect
    assert_not_equal 403, response.status
  end

  private

  def create_user!(email, role)
    User.create!(
      email: email,
      password: "password",
      role: role
    )
  end

  def create_wallet!(user, available_points)
    Wallet.create!(
      customer_user: user,
      available_points: available_points,
      reserved_points: 0
    )
  end
end
