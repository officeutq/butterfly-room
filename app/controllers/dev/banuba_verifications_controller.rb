# frozen_string_literal: true

module Dev
  class BanubaVerificationsController < ApplicationController
    before_action :ensure_development!
    before_action -> { require_at_least!(:system_admin) }

    def show
      @banuba_client_token = ENV["BANUBA_CLIENT_TOKEN"].to_s
      @banuba_sdk_base_url = "/banuba/sdk"
      @banuba_face_tracker_url = "/banuba/modules/face_tracker.zip"
      @banuba_effect_url = "/banuba/effects/glasses_RayBan4165_Dark.zip"
      @banuba_effect_name = "glasses_RayBan4165_Dark.zip"
    end

    private

    def ensure_development!
      head :not_found unless Rails.env.development?
    end
  end
end
