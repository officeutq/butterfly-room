# frozen_string_literal: true

module SystemAdmin
  class SettlementExportsController < SystemAdmin::BaseController
    def index
      @exports = SettlementExport.order(id: :desc).limit(200)
    end

    def show
      @export = SettlementExport.find(params[:id])
    end

    def create
      result = Settlements::SbiFurikomiCsvExportService.new(
        actor_user: current_user
      ).call

      if result[:ok]
        notice =
          if result[:created_exports].size == 1
            "振込CSVを生成しました"
          else
            "振込CSVを#{result[:created_exports].size}ファイル生成しました"
          end

        redirect_to system_admin_settlement_exports_path, notice: notice
      else
        redirect_to system_admin_settlement_exports_path, alert: result[:message]
      end
    end
  end
end
