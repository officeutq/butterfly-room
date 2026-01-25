# frozen_string_literal: true

module Admin
  class DashboardController < Admin::BaseController
    before_action :require_current_store!

    def show
    end
  end
end
