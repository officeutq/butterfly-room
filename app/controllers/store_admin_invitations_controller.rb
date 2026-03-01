# frozen_string_literal: true

class StoreAdminInvitationsController < ApplicationController
  before_action :set_invitation_by_token

  def show
    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path(invite_token: params[:token], invite_kind: "store_admin"),
                  alert: "招待の承認には store_admin でログインしてください"
      return
    end

    # store_admin 以外は案内だけ表示（承認不可）
    unless current_user.store_admin?
      render :show, status: :ok
      return
    end

    # すでに admin membership を持つかチェック
    @already_member = StoreMembership.exists?(
      store_id: @invitation.store_id,
      user_id: current_user.id,
      membership_role: :admin
    )

    # 在籍済み かつ 招待がまだ usable なら closed 扱いにする
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

    unless current_user.store_admin?
      redirect_to store_admin_invitation_path(params[:token]), alert: "store_admin でログインして承認してください"
      return
    end

    StoreAdminInvitations::AcceptInvitation.call!(invitation: @invitation, actor: current_user)

    # ★current_store を招待対象に保証（重要）
    session[:current_store_id] = @invitation.store_id
    session.delete(:current_booth_id)

    redirect_to dashboard_path, notice: "store_admin 招待を承認しました（#{@invitation.store.name}）"
  rescue StoreAdminInvitations::AcceptInvitation::NotUsable => e
    redirect_to store_admin_invitation_path(params[:token]), alert: e.message
  rescue StoreAdminInvitations::AcceptInvitation::NotAuthorized => e
    redirect_to store_admin_invitation_path(params[:token]), alert: e.message
  end

  private

  def set_invitation_by_token
    @invitation = StoreAdminInvitation.find_by_token(params[:token].to_s)
    head :not_found if @invitation.blank?
  end
end
