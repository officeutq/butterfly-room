# frozen_string_literal: true

module Admin
  class OnboardingsController < Admin::BaseController
    before_action :require_current_store!

    def skip
      current_store.skip_onboarding!
      head :ok
    end

    def cast_invitation_copied
      if current_store.store_cast_invitations.exists?
        current_store.mark_onboarding_invite_copied!
      end

      render json: { step: current_store.onboarding_step }
    end
  end
end
