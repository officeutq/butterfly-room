# frozen_string_literal: true

module BuildHelper
  def current_build_number
    Rails.application.config_for(:app_build).fetch(:build_number)
  end

  def current_build_label
    "Butterflyve Build #{current_build_number}"
  end
end
