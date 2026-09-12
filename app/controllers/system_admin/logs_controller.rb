# frozen_string_literal: true

module SystemAdmin
  class LogsController < BaseController
    def index
      @kind = log_kind
      filters = Logs::SearchQuery::FILTER_KEYS.index_with { |key| params[key] }
      @page = Logs::SearchQuery.new(kind: @kind, filters: filters).call
      @filters = @page.filters
      render "system_admin/logs/index"
    end

    def show
      @kind = log_kind
      @entry = { errors: ErrorLog, changes: ChangeLog }.fetch(@kind).includes(:actor_user).find(params[:id])
      render "system_admin/logs/show"
    end
  end
end
