# frozen_string_literal: true

module Admin
  class CastsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @cast_memberships =
        StoreMembership
          .includes(:user)
          .where(store_id: current_store.id, membership_role: :cast)
          .order(:id)

      @store_cast_invitations =
        StoreCastInvitation
          .includes(:invited_by_user, :accepted_by_user)
          .where(store_id: current_store.id)
          .recent_first

      @new_invitation = StoreCastInvitation.new

      @store_admin_invitations =
        StoreAdminInvitation
          .includes(:invited_by_user, :accepted_by_user)
          .where(store_id: current_store.id)
          .recent_first
    end

    # キャスト招待発行（note 任意）
    def invite
      note = params.require(:store_cast_invitation).permit(:note)[:note]

      result =
        StoreCastInvitations::IssueInvitation.call!(
          store: current_store,
          invited_by_user: current_user,
          note: note
        )

      token = result.token
      url = cast_invitation_url(token)

      redirect_to admin_casts_path,
                  notice: "招待を発行しました: #{url}"
    rescue ActionController::ParameterMissing
      redirect_to admin_casts_path, alert: "パラメータが不正です"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_casts_path, alert: e.record.errors.full_messages.join(", ")
    end

    # store_admin 招待発行（note なし）
    def invite_store_admin
      result =
        StoreAdminInvitations::IssueInvitation.call!(
          store: current_store,
          invited_by_user: current_user
        )

      token = result.token
      url = store_admin_invitation_url(token)

      redirect_to admin_casts_path,
                  notice: "招待を発行しました: #{url}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_casts_path, alert: e.record.errors.full_messages.join(", ")
    end

    def destroy
      membership =
        StoreMembership
          .where(store_id: current_store.id, membership_role: :cast)
          .find(params[:id])

      membership.destroy!

      redirect_to admin_casts_path, notice: "キャスト登録を解除しました"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
