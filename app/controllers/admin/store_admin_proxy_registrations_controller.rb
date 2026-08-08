# frozen_string_literal: true

module Admin
  class StoreAdminProxyRegistrationsController < Admin::BaseController
    before_action :require_current_store!
    before_action :require_store_admin_registration_proxy!

    def new
      @form = StoreAdminRegistrations::ProxyForm.new(store: current_store, actor: current_user)
    end

    def create
      @form = StoreAdminRegistrations::ProxyForm.new(
        proxy_registration_params.merge(store: current_store, actor: current_user)
      )

      if @form.save
        redirect_to admin_store_admin_invitations_path, flash_for(@form.result)
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def proxy_registration_params
      params.require(:store_admin_proxy_registration).permit(:display_name, :email)
    end

    def require_store_admin_registration_proxy!
      allowed =
        current_user.store_registration_proxy_allowed? &&
        current_user.admin_of_store?(current_store.id)

      head :forbidden unless allowed
    end

    def flash_for(result)
      unless result.mail_delivered
        return {
          alert: "店舗責任者の登録内容は保存しましたが、案内メールを送信できませんでした。代行用フォームから再送してください"
        }
      end

      message =
        case result.status
        when :created
          "店舗責任者を登録し、パスワード設定案内を送信しました"
        when :added_to_store
          "既存の店舗管理者を追加し、案内メールを送信しました"
        when :already_member
          "この店舗責任者はすでに登録済みです。案内メールを再送しました"
        end

      { notice: message }
    end
  end
end
