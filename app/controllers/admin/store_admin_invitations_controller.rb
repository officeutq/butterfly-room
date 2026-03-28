# frozen_string_literal: true

module Admin
  class StoreAdminInvitationsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @store_admin_invitations =
        StoreAdminInvitation
          .includes(:invited_by_user, :accepted_by_user)
          .where(store_id: current_store.id)
          .recent_first
    end

    def create
      result =
        StoreAdminInvitations::IssueInvitation.call!(
          store: current_store,
          invited_by_user: current_user
        )

      token = result.token
      url = store_admin_invitation_url(token)

      result.invitation.update!(issued_url: url)

      redirect_to admin_store_admin_invitations_path,
                  notice: "招待を発行しました: #{url}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_store_admin_invitations_path, alert: e.record.errors.full_messages.join(", ")
    end
  end
end
