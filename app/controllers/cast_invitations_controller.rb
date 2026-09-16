# frozen_string_literal: true

class CastInvitationsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[show]
  before_action :set_invitation_by_token

  def show
    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      render :show, status: :ok
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

    if @invitation.usable?
      @already_member = StoreCastInvitations::AcceptInvitation.consume_if_already_member!(
        invitation: @invitation, actor: current_user)
    end

    render :show, status: :ok
  rescue StoreCastInvitations::AcceptInvitation::NotAuthorized => e
    @acceptance_restriction = e.message
    render :show, status: :ok
  end

  def accept
    authenticate_user!

    unless current_user.cast?
      redirect_to cast_invitation_path(params[:token]), alert: "cast でログインして承認してください"
      return
    end

    result = StoreCastInvitations::AcceptInvitation.call!(invitation: @invitation, actor: current_user)

    selection = resolve_current_selection(purpose: :invitation_accepted, target_id: result.booth.id)
    unless save_current_selection(selection)
      return redirect_to dashboard_path, notice: "キャスト招待を承認しました", alert: selection_error_message(selection)
    end
    notice = "キャスト招待を承認しました。ブースを『#{result.booth.store.name}』の『#{result.booth.name}』に切り替えました。"
    session[:invitation_booth_edit_id] = result.booth.id

    if session.delete(:just_registered_via_cast_invitation)
      session[:redirect_to_booth_edit_after_profile_update] = true
      redirect_to edit_profile_path, notice: notice
    else
      session[:redirect_to_home_after_cast_booth_update] = true
      redirect_to edit_cast_booth_path(result.booth), notice: notice
    end
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
