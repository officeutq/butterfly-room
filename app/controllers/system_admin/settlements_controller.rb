# frozen_string_literal: true

module SystemAdmin
  class SettlementsController < SystemAdmin::BaseController
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

    def form_params
      params.require(:manual_settlement).permit(:store_id, :period_from, :period_to)
    end
  end
end
