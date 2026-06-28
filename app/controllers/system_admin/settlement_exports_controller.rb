# frozen_string_literal: true

module SystemAdmin
  class SettlementExportsController < SystemAdmin::BaseController
    def index
      @exports = SettlementExport.order(id: :desc).limit(200)
    end

    def show
      @export = SettlementExport.find(params[:id])
    end
  end
end
