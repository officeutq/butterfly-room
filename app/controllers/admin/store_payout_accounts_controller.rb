# frozen_string_literal: true

module Admin
  class StorePayoutAccountsController < Admin::BaseController
    before_action :require_current_store!
    before_action :set_store
    before_action :authorize_store!

    def edit
      @active_payout_account = @store.active_payout_account

      # 事故防止：既存口座情報をフォームにプリフィルしない（フル表示回避）
      @payout_account = @store.store_payout_accounts.new(
        payout_method: :manual_bank,
        status: :active
      )
    end

    def update
      @active_payout_account = @store.active_payout_account

      @payout_account = @store.store_payout_accounts.new(payout_account_params)
      @payout_account.payout_method = :manual_bank
      @payout_account.status = :active
      @payout_account.updated_by_user = current_user

      # 新規が valid でない限り、既存 active を触らない（事故防止）
      unless @payout_account.valid?
        render :edit, status: :unprocessable_entity
        return
      end

      StorePayoutAccount.transaction do
        @active_payout_account&.update!(status: :inactive, updated_by_user: current_user)
        @payout_account.save!
      end

      redirect_to edit_admin_payout_account_path, notice: "精算・振込設定を更新しました"
    end

    private

    def set_store
      @store = current_store
    end

    def authorize_store!
      return if current_user.system_admin?

      ok = StoreMembership.admin_only.exists?(user_id: current_user.id, store_id: @store.id)
      head :forbidden unless ok
    end

    def payout_account_params
      params.require(:store_payout_account).permit(
        :input_account_kind,
        :bank_code,
        :branch_code,
        :account_type,
        :account_number,
        :account_holder_kana,
        :jp_bank_symbol,
        :jp_bank_number
      )
    end
  end
end
