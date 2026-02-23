# frozen_string_literal: true

class BoothsController < ApplicationController
  include StoreBanGuard

  before_action :set_booth, only: %i[show enter enter_as_cast]
  before_action :reject_banned_customer_for_booth!, only: %i[show]

  def show
    @stream_session = @booth.current_stream_session
    @drink_items = @booth.store.drink_items.enabled_only.ordered

    @wallet =
      if user_signed_in?
        Wallet.find_or_create_by!(customer_user_id: current_user.id) do |w|
          w.available_points = 0
          w.reserved_points = 0
        end
      end

    @comments =
      if @stream_session.present?
        Comment.alive.where(stream_session: @stream_session)
              .order(created_at: :desc)
              .limit(50)
              .reverse
      else
        []
      end

    @booth_favorited =
      user_signed_in? && current_user.favorite_booths.exists?(booth_id: @booth.id)
  end

  # ブースカードクリック導線（ロール/権限で分岐）
  def enter
    # guest は customer と同じ（視聴）
    unless user_signed_in?
      redirect_to booth_path(@booth)
      return
    end

    # customer は常に視聴
    if current_user.customer?
      redirect_to booth_path(@booth)
      return
    end

    # cast（本人ブースなら即配信 / 他人ブースは視聴）
    if current_user.cast?
      if BoothCast.exists?(cast_user_id: current_user.id, booth_id: @booth.id)
        set_current_context_for_booth!
        redirect_to live_cast_booth_path(@booth)
      else
        redirect_to booth_path(@booth)
      end
      return
    end

    # store_admin（自店なら選択UI / 他店なら視聴）
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

    # system_admin（常に選択UI）
    if current_user.system_admin?
      if turbo_frame_request?
        render partial: "booths/enter_modal", locals: { booth: @booth }, layout: false, status: :ok
      else
        render :enter, status: :ok
      end
      return
    end

    # 想定外は安全側（視聴）
    redirect_to booth_path(@booth)
  end

  # 「配信する」選択 → session更新 → cast live へ
  def enter_as_cast
    require_at_least!(:cast)

    allowed =
      if current_user.system_admin?
        true
      elsif current_user.store_admin?
        current_user.admin_of_store?(@booth.store_id)
      else
        BoothCast.exists?(cast_user_id: current_user.id, booth_id: @booth.id)
      end

    head :forbidden unless allowed
    return unless allowed

    set_current_context_for_booth!
    redirect_to live_cast_booth_path(@booth)
  end

  private

  def set_booth
    @booth = Booth.active.find(params[:id])
  end

  def reject_banned_customer_for_booth!
    reject_banned_customer!(store: @booth.store)
  end

  def set_current_context_for_booth!
    session[:current_booth_id] = @booth.id
    session[:current_store_id] = @booth.store_id
  end
end
