# frozen_string_literal: true

class CastInvitationsController < ApplicationController
  before_action :set_invitation_by_token

  def show
    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path(invite_token: params[:token]), alert: "招待の承認には cast でログインしてください"
      return
    end

    # cast以外は案内だけ表示（承認不可）
    unless current_user.cast?
      render :show, status: :ok
      return
    end

    @already_member = StoreMembership.exists?(
      store_id: @invitation.store_id,
      user_id: current_user.id,
      membership_role: :cast
    )

    if @already_member && @invitation.usable?
      ActiveRecord::Base.transaction do
        @invitation.lock!

        if @invitation.usable?
          @invitation.update!(
            used_at: Time.current,
            accepted_by_user: current_user
          )
        end
      end
    end

    render :show, status: :ok
  end

  def accept
    authenticate_user!

    unless current_user.cast?
      redirect_to cast_invitation_path(params[:token]), alert: "cast でログインして承認してください"
      return
    end

    result = StoreCastInvitations::AcceptInvitation.call!(invitation: @invitation, actor: current_user)

    session[:current_booth_id] = result.booth.id
    session[:current_store_id] = result.booth.store_id

    redirect_to root_path, notice: "キャスト招待を承認しました（#{@invitation.store.name}）"
  rescue StoreCastInvitations::AcceptInvitation::NotUsable => e
    redirect_to cast_invitation_path(params[:token]), alert: e.message
  rescue StoreCastInvitations::AcceptInvitation::NotAuthorized => e
    redirect_to cast_invitation_path(params[:token]), alert: e.message
  end

  private

  def set_invitation_by_token
    @invitation = StoreCastInvitation.find_by_token(params[:token].to_s)
    head :not_found if @invitation.blank?
  end
end
