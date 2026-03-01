# frozen_string_literal: true

module SystemAdmin
  class SettlementsController < SystemAdmin::BaseController
    before_action :set_settlement, only: %i[show confirm mark_paid]

    # ----------------------------
    # #260 List
    # ----------------------------
    def index
      scope = Settlement.includes(:store).order(period_from: :desc, id: :desc)

      # defaults: recent 3 months + statuses draft/confirmed/exported
      @status_options = Settlement.statuses.keys
      @kind_options = Settlement.kinds.keys
      @stores = Store.order(id: :desc)

      statuses = Array(params[:statuses]).presence || %w[draft confirmed exported]
      kinds = Array(params[:kinds]).presence

      if statuses.present?
        scope = scope.where(status: statuses)
      end

      if kinds.present?
        scope = scope.where(kind: kinds)
      end

      if params[:store_id].present?
        scope = scope.where(store_id: params[:store_id])
      end

      if params[:month].present?
        # month: "2026-02" 想定
        begin
          month_date = Date.strptime("#{params[:month]}-01", "%Y-%m-%d")
          from = month_date.beginning_of_month.in_time_zone("Asia/Tokyo")
          to = (month_date.next_month.beginning_of_month).in_time_zone("Asia/Tokyo")
          scope = scope.where(period_from: from...to)
        rescue ArgumentError
          # ignore invalid month
        end
      else
        # recent 3 months
        from = Time.use_zone("Asia/Tokyo") { 3.months.ago.beginning_of_month }
        scope = scope.where("period_from >= ?", from)
      end

      @settlements = scope
    end

    # ----------------------------
    # #260 Detail
    # ----------------------------
    def show
      @events = @settlement.settlement_events.includes(:actor_user).order(created_at: :desc, id: :desc)
    end

    # ----------------------------
    # #260 draft -> confirmed
    # ----------------------------
    def confirm
      unless @settlement.draft?
        redirect_to system_admin_settlement_path(@settlement), alert: "draft のみ確定できます"
        return
      end

      @settlement.update!(
        status: :confirmed,
        confirmed_at: Time.use_zone("Asia/Tokyo") { Time.zone.now }
      )

      @settlement.settlement_events.create!(
        actor_user: current_user,
        action: :confirmed
      )

      redirect_to system_admin_settlement_path(@settlement), notice: "confirmed に更新しました"
    end

    # ----------------------------
    # #260 bulk export (selected confirmed -> 1 file)
    # partial success prohibited
    # ----------------------------
    def export_csv
      ids = Array(params[:settlement_ids]).map(&:to_i).uniq
      if ids.empty?
        redirect_to system_admin_settlements_path, alert: "対象の精算を選択してください"
        return
      end

      settlements = Settlement.includes(:store).where(id: ids).order(:id).to_a
      if settlements.size != ids.size
        redirect_to system_admin_settlements_path, alert: "存在しない精算が含まれています"
        return
      end

      # must all be confirmed
      not_confirmed = settlements.reject(&:confirmed?)
      if not_confirmed.any?
        redirect_to system_admin_settlements_path, alert: "confirmed 以外が含まれています（id=#{not_confirmed.map(&:id).join(',')}）"
        return
      end

      # payout must be present for all (manual_bank only)
      missing = settlements.select { |s| StorePayoutAccount.where(store_id: s.store_id, status: StorePayoutAccount.statuses[:active], payout_method: StorePayoutAccount.payout_methods[:manual_bank]).none? }
      if missing.any?
        redirect_to system_admin_settlements_path, alert: "振込口座（manual_bank）が未設定の店舗が含まれています（settlement_id=#{missing.map(&:id).join(',')}）"
        return
      end

      result = Settlements::SbiFurikomiCsvExportService.new(
        actor_user: current_user,
        settlements: settlements
      ).call

      unless result[:ok]
        redirect_to system_admin_settlements_path, alert: result[:message]
        return
      end

      redirect_to system_admin_settlement_exports_path, notice: "振込CSVを生成しました"
    end

    # ----------------------------
    # #260 exported -> paid
    # with extra confirmation checkbox
    # ----------------------------
    def mark_paid
      unless @settlement.exported?
        redirect_to system_admin_settlement_path(@settlement), alert: "exported のみ支払済みにできます"
        return
      end

      unless params[:paid_confirm].to_s == "1"
        redirect_to system_admin_settlement_path(@settlement), alert: "確認チェックが必要です"
        return
      end

      @settlement.update!(status: :paid)

      @settlement.settlement_events.create!(
        actor_user: current_user,
        action: :marked_paid
      )

      redirect_to system_admin_settlement_path(@settlement), notice: "paid に更新しました"
    end

    # ----------------------------
    # manual settlement (existing)
    # ----------------------------
    def new_manual
      @form = ManualSettlementForm.new
      @preview = nil
    end

    def preview_manual
      @form = ManualSettlementForm.new(form_params)

      if @form.valid?
        @preview = Settlements::ManualPreviewService.new(
          store_id: @form.store_id,
          period_from: @form.period_from,
          period_to: @form.period_to
        ).call
        render :new_manual
      else
        @preview = nil
        render :new_manual, status: :unprocessable_entity
      end
    end

    def create_manual
      @form = ManualSettlementForm.new(form_params)

      unless @form.valid?
        @preview = nil
        render :new_manual, status: :unprocessable_entity
        return
      end

      result = Settlements::ManualCreateService.new(
        store_id: @form.store_id,
        period_from: @form.period_from,
        period_to: @form.period_to,
        actor_user: current_user
      ).call

      if result[:ok]
        redirect_to dashboard_path, notice: "マニュアル精算を作成しました（confirmed）"
        return
      end

      @preview = Settlements::ManualPreviewService.new(
        store_id: @form.store_id,
        period_from: @form.period_from,
        period_to: @form.period_to
      ).call

      @form.errors.add(:base, result[:message])
      render :new_manual, status: :unprocessable_entity
    end

    private

    def set_settlement
      @settlement = Settlement.includes(:store).find(params[:id])
    end

    def form_params
      params.require(:manual_settlement).permit(:store_id, :period_from, :period_to)
    end
  end
end
