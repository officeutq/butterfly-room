# frozen_string_literal: true

module Admin
  class CastInvitationsController < Admin::BaseController
    before_action :set_invitation, only: %i[update destroy shared]
    rescue_from StoreCastInvitations::UpdateInvitation::Conflict, with: :conflict

    def index
      if entry_store.present?
        redirect_to admin_casts_path(tab: "invitations")
      else
        redirect_to select_modal_admin_stores_path(return_to: admin_casts_path(tab: "invitations"))
      end
    end

    def new
      unless turbo_frame_request?
        redirect_to dashboard_path
        return
      end
      @store = entry_store
      unless @store
        redirect_to select_modal_admin_stores_path(return_to_key: "cast_invitation")
        return
      end
      @request_key = SecureRandom.uuid
      render :new, layout: false
    end

    def create
      store = authorized_store(params.require(:store_id))
      key = params.require(:request_key).to_s
      raise ArgumentError, "発行リクエストが不正です" unless key.match?(/\A[0-9a-f-]{36}\z/)

      result = StoreCastInvitations::IssueInvitation.call!(
        store: store, invited_by_user: current_user, request_key: key,
        url_builder: ->(token) { cast_invitation_url(token) }
      )
      @invitation = result.invitation
      render json: invitation_payload.merge(
        url: @invitation.issued_url,
        note: @invitation.note.to_s,
        expires_at: I18n.l(@invitation.expires_at),
        update_url: admin_cast_invitation_path(@invitation),
        shared_url: shared_admin_cast_invitation_path(@invitation),
        text: helpers.cast_invitation_share_text(@invitation)
      )
    rescue ActionController::ParameterMissing, ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join("、") }, status: :unprocessable_entity
    end

    def update
      note = params.require(:store_cast_invitation).permit(:note).fetch(:note, "")
      StoreCastInvitations::UpdateInvitation.call!(invitation: @invitation, action: :note, note: note)
      render json: invitation_payload
    end

    def destroy
      StoreCastInvitations::UpdateInvitation.call!(invitation: @invitation, action: :cancel)
      render json: invitation_payload
    end

    def shared
      StoreCastInvitations::UpdateInvitation.call!(invitation: @invitation, action: :shared)
      render json: invitation_payload
    end

    private

    # ダッシュボードと同じく、最初の管理者所属への補完より先に選択を挟む。
    def entry_store
      booth = helpers.layout_current_booth
      return booth.store if booth
      return if session[:current_store_id].blank?
      authorized_store(session[:current_store_id])
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def authorized_store(id)
      return Store.find(id) if current_user.system_admin?
      Store.joins(:store_memberships).where(store_memberships: {
        user_id: current_user.id, membership_role: :admin
      }).find(id)
    end

    def set_invitation
      @invitation = StoreCastInvitation.find(params[:id])
      authorized_store(@invitation.store_id)
    end

    def invitation_payload
      { store_id: @invitation.store_id, step: @invitation.store.reload.onboarding_step,
        shared: @invitation.shared_at.present?, cancelled: @invitation.cancelled? }
    end

    def conflict(error)
      render json: { error: error.message }, status: :conflict
    end
  end
end
