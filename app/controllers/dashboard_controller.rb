# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    store = layout_current_store_for_onboarding
    store&.advance_onboarding_to_setup_drinks!
  end

  private

  def layout_current_store_for_onboarding
    return nil unless user_signed_in?

    booth_id = session[:current_booth_id]
    if booth_id.present?
      booth = Booth.find_by(id: booth_id)
      return booth.store if booth.present?
    end

    store_id = session[:current_store_id]
    return nil if store_id.blank?

    store = Store.find_by(id: store_id)
    return nil if store.blank?

    return store if current_user.system_admin?
    return store if current_user.at_least?(:store_admin) && current_user.admin_of_store?(store.id)

    nil
  end
end
