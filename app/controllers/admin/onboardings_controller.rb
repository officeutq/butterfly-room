# frozen_string_literal: true

module Admin
  class OnboardingsController < Admin::BaseController
    before_action :require_current_store!, only: :cast_invitation_copied

    def skip
      store = params[:store_id].present? ? Store.find(params[:store_id]) : current_store
      return head :not_found unless store
      return head :forbidden unless current_user.system_admin? || current_user.admin_of_store?(store.id)
      Stores::AdvanceOnboarding.call!(store: store, action: :skip)
      head :ok
    end

    def cast_invitation_copied
      # 旧クライアントからの通知では進めない。招待IDを認可するsharedへ移行。
      render json: { step: current_store.onboarding_step }
    end
  end
end
