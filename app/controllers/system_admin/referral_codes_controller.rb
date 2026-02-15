# frozen_string_literal: true

module SystemAdmin
  class ReferralCodesController < SystemAdmin::BaseController
    before_action :set_referral_code, only: %i[edit update]

    def index
      @referral_codes = ReferralCode.order(id: :desc)
    end

    def new
      @referral_code = ReferralCode.new(enabled: true)
    end

    def create
      @referral_code = ReferralCode.new(referral_code_params)

      if @referral_code.save
        redirect_to system_admin_referral_codes_path, notice: "紹介コードを作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @referral_code.update(referral_code_params)
        redirect_to system_admin_referral_codes_path, notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_referral_code
      @referral_code = ReferralCode.find(params[:id])
    end

    def referral_code_params
      params.require(:referral_code).permit(:code, :label, :expires_at, :enabled)
    end
  end
end
