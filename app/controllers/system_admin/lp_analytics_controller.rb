# frozen_string_literal: true

module SystemAdmin
  class LpAnalyticsController < SystemAdmin::BaseController
    def index
      @filter = LpAnalytics::AnalysisFilter.new(params: filter_params)
      @analysis = LpAnalytics::AnalysisQuery.new(filter: @filter).call
      @recent_conversions = LpAnalytics::RecentConversionsQuery.new(
        filter: @filter,
        page: params[:page]
      ).call
      @dimension_options = LpAnalytics::DimensionOptionsQuery.new.call
    end

    def show
      @visit_detail = LpAnalytics::VisitDetailQuery.new(public_id: params[:public_id]).call
    end

    private

    def filter_params
      params.permit(
        :period,
        :start_date,
        :end_date,
        :lp_identifier,
        :traffic_source,
        :utm_source,
        :utm_campaign,
        :utm_content,
        :device_type
      )
    end
  end
end
