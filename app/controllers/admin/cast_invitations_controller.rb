# frozen_string_literal: true

module Admin
  class CastInvitationsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @store_cast_invitations =
        StoreCastInvitation
          .includes(:invited_by_user, :accepted_by_user)
          .where(store_id: current_store.id)
          .recent_first

      @new_invitation = StoreCastInvitation.new
    end

    def create
      note = params.require(:store_cast_invitation).permit(:note)[:note]

      result =
        StoreCastInvitations::IssueInvitation.call!(
          store: current_store,
          invited_by_user: current_user,
          note: note
        )

      token = result.token
      url = cast_invitation_url(token)

      result.invitation.update!(issued_url: url)

      redirect_to admin_cast_invitations_path,
                  notice: "招待を発行しました: #{url}"
    rescue ActionController::ParameterMissing
      redirect_to admin_cast_invitations_path, alert: "パラメータが不正です"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_cast_invitations_path, alert: e.record.errors.full_messages.join(", ")
    end
  end
end
