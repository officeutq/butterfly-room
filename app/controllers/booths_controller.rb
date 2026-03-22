# frozen_string_literal: true

class BoothsController < ApplicationController
  include StoreBanGuard

  before_action :set_booth, only: %i[show enter enter_as_cast viewer_drink_menu]
  before_action :reject_banned_customer_for_booth!, only: %i[show viewer_drink_menu]
  before_action :set_viewer_stream_context, only: %i[show viewer_drink_menu]

  def show
    @wallet =
      if user_signed_in?
        Wallet.find_or_create_by!(customer_user_id: current_user.id) do |w|
          w.available_points = 0
          w.reserved_points = 0
        end
      end

    @comments = load_viewer_comments

    @booth_favorited =
      user_signed_in? && current_user.favorite_booths.exists?(booth_id: @booth.id)

    @store_favorited =
      user_signed_in? && current_user.favorite_stores.exists?(store_id: @booth.store_id)
  end

  def viewer_drink_menu
    render partial: "booths/drink_menu",
           locals: {
             booth: @booth,
             stream_session: @stream_session,
             drink_items: @drink_items,
             can_create_drink_order: @can_create_drink_order
           },
           layout: false,
           status: :ok
  end

  def enter
    unless user_signed_in?
      redirect_to booth_path(@booth)
      return
    end

    if current_user.customer?
      redirect_to booth_path(@booth)
      return
    end

    if current_user.cast?
      if BoothCast.exists?(cast_user_id: current_user.id, booth_id: @booth.id)
        set_current_context_for_booth!

        result = ::Booths::EnterAsCastService.new(
          booth: @booth,
          actor: current_user
        ).call

        case result.action
        when :redirect_live
          redirect_to live_cast_booth_path(result.booth)
        when :occupied_by_other
          redirect_back fallback_location: root_path, alert: "このブースはすでに配信中です"
        else
          redirect_back fallback_location: root_path, alert: "配信導線の開始に失敗しました"
        end
      else
        redirect_to booth_path(@booth)
      end
      return
    end

    if current_user.store_admin?
      if current_user.admin_of_store?(@booth.store_id)
        if turbo_frame_request?
          render partial: "booths/enter_modal", locals: { booth: @booth }, layout: false, status: :ok
        else
          render :enter, status: :ok
        end
      else
        redirect_to booth_path(@booth)
      end
      return
    end

    if current_user.system_admin?
      if turbo_frame_request?
        render partial: "booths/enter_modal", locals: { booth: @booth }, layout: false, status: :ok
      else
        render :enter, status: :ok
      end
      return
    end

    redirect_to booth_path(@booth)
  rescue ::Booths::EnterAsCastService::NotAuthorized
    head :forbidden
  end

  def enter_as_cast
    require_at_least!(:cast)

    set_current_context_for_booth!

    result = ::Booths::EnterAsCastService.new(
      booth: @booth,
      actor: current_user
    ).call

    case result.action
    when :redirect_live
      redirect_to live_cast_booth_path(result.booth)
    when :occupied_by_other
      redirect_back fallback_location: root_path, alert: "このブースはすでに配信中です"
    else
      redirect_back fallback_location: root_path, alert: "配信導線の開始に失敗しました"
    end
  rescue ::Booths::EnterAsCastService::NotAuthorized
    head :forbidden
  end

  private

  def set_booth
    @booth = Booth.active.find(params[:id])
  end

  def set_viewer_stream_context
    @stream_session = @booth.current_stream_session
    @drink_items = @booth.store.drink_items.enabled_only.ordered
    @can_create_drink_order = can_create_drink_order?
  end

  def can_create_drink_order?
    return false unless @stream_session.present? && user_signed_in?

    Authorization::ViewerPolicy.new(current_user, @stream_session).create_drink_order?
  end

  def load_viewer_comments
    return [] unless @stream_session.present?

    Comment.alive.where(stream_session: @stream_session)
           .order(created_at: :desc)
           .limit(50)
           .reverse
  end

  def reject_banned_customer_for_booth!
    reject_banned_customer!(store: @booth.store)
  end

  def set_current_context_for_booth!
    session[:current_booth_id] = @booth.id
    session[:current_store_id] = @booth.store_id
  end
end
