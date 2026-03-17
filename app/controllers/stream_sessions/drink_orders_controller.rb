# frozen_string_literal: true

module StreamSessions
  class DrinkOrdersController < ApplicationController
    include StoreBanGuard

    before_action :authenticate_user!
    before_action :set_stream_session
    before_action :authorize_create_drink_order!
    before_action :reject_banned_customer_for_stream_session!

    def create
      drink_item_id = params[:drink_item_id] || params.dig(:drink_order, :drink_item_id)
      drink_item = DrinkItem.find(drink_item_id)

      result = DrinkOrders::CreateService.new(
        stream_session: @stream_session,
        customer_user: current_user,
        drink_item: drink_item
      ).call!

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "drink_menu",
              partial: "booths/drink_menu",
              formats: [ :html ],
              locals: {
                booth: @stream_session.booth,
                stream_session: @stream_session,
                drink_items: DrinkItem.where(store_id: @stream_session.store_id, enabled: true).order(:id),
                can_create_drink_order: true
              }
            ),
            turbo_stream.append(
              "flash_inner",
              partial: "shared/flash_message",
              locals: { level: "success", message: "ドリンクを送信しました" }
            )
          ]
        end

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
          redirect_back fallback_location: booth_path(@stream_session.booth_id),
                        notice: "ドリンクを送信しました"
        end
      end
    rescue Wallets::HoldService::InsufficientPoints
      render_drink_menu_error("ポイント不足です")
    rescue DrinkOrders::CreateService::Conflict
      render_drink_menu_error("配信中のみドリンク送信できます")
    rescue DrinkOrders::CreateService::InvalidItem
      render_drink_menu_error("このドリンクは送信できません")
    rescue DrinkOrders::CreateService::Forbidden
      render_drink_menu_error("送信できません（forbidden）", status: :forbidden)
    end

    private

    def set_stream_session
      @stream_session = StreamSession.find(params[:stream_session_id])
    end

    def authorize_create_drink_order!
      policy = Authorization::ViewerPolicy.new(current_user, @stream_session)
      head :forbidden unless policy.create_drink_order?
    end

    def reject_banned_customer_for_stream_session!
      reject_banned_customer!(store: @stream_session.store)
    end

    def render_drink_menu_error(message, status: :ok)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "drink_menu",
              partial: "booths/drink_menu",
              formats: [ :html ],
              locals: {
                booth: @stream_session.booth,
                stream_session: @stream_session,
                drink_items: DrinkItem.where(store_id: @stream_session.store_id, enabled: true).order(:id),
                can_create_drink_order: true
              }
            ),
            turbo_stream.append(
              "flash_inner",
              partial: "shared/flash_message",
              locals: { level: "danger", message: message }
            )
          ], status: status
        end

        format.json do
          code =
            case message
            when /ポイント不足/ then "insufficient_points"
            when /配信中/       then "booth_not_live"
            when /送信できません（forbidden）/ then "forbidden"
            else "invalid"
            end
          http_status =
            case code
            when "insufficient_points" then :payment_required
            when "booth_not_live"      then :conflict
            when "forbidden"           then :forbidden
            else :unprocessable_entity
            end
          render json: { error: code }, status: http_status
        end

        format.html do
          redirect_back fallback_location: booth_path(@stream_session.booth_id), alert: message
        end
      end
    end
  end
end
