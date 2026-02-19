# frozen_string_literal: true

class Cast::DrinkOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action -> { require_at_least!(:cast) }

  def consume
    result = DrinkOrders::ConsumeService.new(drink_order_id: params[:id]).call!
    render json: { drink_order_id: result.drink_order.id }, status: :ok
  rescue DrinkOrders::ConsumeService::NotHeadError
    render json: { error: "not_head" }, status: :conflict
  rescue DrinkOrders::ConsumeService::InvalidStatusError
    render json: { error: "not_pending" }, status: :conflict
  rescue DrinkOrders::ConsumeService::MissingWalletError
    render json: { error: "missing_wallet" }, status: :conflict
  rescue Wallets::ConsumeService::InsufficientReservedPoints
    render json: { error: "insufficient_reserved_points" }, status: :conflict
  end
end
