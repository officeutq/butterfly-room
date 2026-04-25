# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    store = layout_current_store_for_onboarding
    store&.advance_onboarding_to_setup_drinks!

    @selectable_stores_count = selectable_stores.count
    @selectable_booths_count = selectable_booths.count
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

  def selectable_stores
    if current_user.system_admin?
      Store.all
    else
      Store
        .joins(:store_memberships)
        .where(store_memberships: {
          user_id: current_user.id,
          membership_role: StoreMembership.membership_roles[:admin]
        })
        .distinct
    end
  end

  def selectable_booths
    if current_user.system_admin?
      Booth.all
    elsif current_user.at_least?(:store_admin)
      Booth
        .joins(store: :store_memberships)
        .where(store_memberships: {
          user_id: current_user.id,
          membership_role: StoreMembership.membership_roles[:admin]
        })
        .distinct
    else
      Booth
        .joins(:booth_casts)
        .where(booth_casts: { cast_user_id: current_user.id })
        .distinct
    end
  end
end
