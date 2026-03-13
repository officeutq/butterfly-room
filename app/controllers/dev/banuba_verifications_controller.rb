# frozen_string_literal: true

module Dev
  class BanubaVerificationsController < ApplicationController
    before_action :ensure_development!
    before_action -> { require_at_least!(:system_admin) }

    def show
      @banuba_client_token = ENV["BANUBA_CLIENT_TOKEN"].to_s
      @banuba_sdk_base_url = "/banuba/sdk"
      @banuba_face_tracker_url = "/banuba/modules/face_tracker.zip"
      @banuba_eyes_url = "/banuba/modules/eyes.zip"
      @banuba_lips_url = "/banuba/modules/lips.zip"
      @banuba_skin_url = "/banuba/modules/skin.zip"
      @banuba_effect_url = "/banuba/effects/beauty_base.zip"
      @banuba_effect_name = "beauty_base.zip"
    end

    private

    def ensure_development!
      head :not_found unless Rails.env.development?
    end
  end
end
