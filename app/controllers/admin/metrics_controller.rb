# frozen_string_literal: true

module Admin
  class MetricsController < Admin::BaseController
    before_action :require_current_store!

    def cast
      # Phase1: 直近30日固定（Query側デフォルト）
      @rows = CastMetricsQuery.new(store: current_store).call
    end
  end
end
