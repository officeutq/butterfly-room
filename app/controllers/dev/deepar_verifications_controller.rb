# frozen_string_literal: true

module Dev
  class DeeparVerificationsController < ApplicationController
    before_action :ensure_development!
    before_action -> { require_at_least!(:system_admin) }

    def show
      @deepar_license_key = ENV["DEEPAR_LICENSE_KEY"].to_s
      @deepar_root_path = "/deepar"
      @deepar_script_url = "/deepar/js/deepar.js"

      @deepar_default_effect_url = "/deepar/effects/aviators"
      @deepar_effect_options = [
        { label: "Aviators", url: "/deepar/effects/aviators" },
        { label: "Lion", url: "/deepar/effects/lion" },
        { label: "Koala", url: "/deepar/effects/koala" },
        { label: "Dalmatian", url: "/deepar/effects/dalmatian" },
        { label: "Galaxy", url: "/deepar/effects/galaxy_background" },
        { label: "Background Blur", url: "/deepar/effects/background_blur.deepar" },
        { label: "Background Replace", url: "/deepar/effects/background_replacement.deepar" }
      ]
    end

    private

    def ensure_development!
      head :not_found unless Rails.env.development?
    end
  end
end
