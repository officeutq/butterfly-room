# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    store = current_store
    Stores::AdvanceOnboarding.call!(store: store, action: :dashboard) if store

    @selectable_stores_count = current_selection.stores.size
    @cast_booths_count = current_selection.booths.size
  end
end
