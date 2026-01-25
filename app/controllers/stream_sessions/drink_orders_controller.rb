# frozen_string_literal: true

module StreamSessions
  class DrinkOrdersController < ApplicationController
    include StoreBanGuard

    before_action :authenticate_user!
    before_action :require_customer!
    before_action :set_stream_session
    before_action :reject_banned_customer_for_stream_session!

    def create
      stream_session = StreamSession.find(params[:stream_session_id])
      drink_item = DrinkItem.find(params[:drink_item_id])

      result = DrinkOrders::CreateService.new(
        stream_session: stream_session,
        customer_user: current_user,
        drink_item: drink_item
      ).call!

      respond_to do |format|
        format.json do
          render json: {
            drink_order_id: result.drink_order.id,
            wallet: {
              available_points: result.wallet.available_points,
              reserved_points:  result.wallet.reserved_points
            }
          }, status: :created
        end
        format.html do
          redirect_back fallback_location: booth_path(stream_session.booth_id),
                        notice: "ドリンクを送信しました"
        end
      end
    rescue Wallets::HoldService::InsufficientPoints
      respond_to do |format|
        format.json { render json: { error: "insufficient_points" }, status: :payment_required } # 402
        format.html { redirect_back fallback_location: booth_path(stream_session.booth_id), alert: "ポイント不足です" }
      end
    rescue DrinkOrders::CreateService::Forbidden
      render json: { error: "forbidden" }, status: :forbidden
    rescue DrinkOrders::CreateService::Conflict
      render json: { error: "booth_not_live" }, status: :conflict
    rescue DrinkOrders::CreateService::InvalidItem
      render json: { error: "invalid_item" }, status: :unprocessable_entity
    end

    private

    def set_stream_session
      @stream_session = StreamSession.find(params[:stream_session_id])
    end

    def reject_banned_customer_for_stream_session!
      reject_banned_customer!(store: @stream_session.store)
    end

    def require_customer!
      head :forbidden unless current_user.customer?
    end
  end
end
