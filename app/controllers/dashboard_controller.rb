# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    store = current_store
    Stores::AdvanceOnboarding.call!(store: store, actor: current_user, action: :dashboard) if store
  end
end
