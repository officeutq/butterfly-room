# frozen_string_literal: true

module Admin
  class CurrentStoresController < Admin::BaseController
    def create
      store_id = params.require(:store_id)

      # session 改ざん対策：必ず membership チェック
      unless StoreMembership.exists?(
        user_id: current_user.id,
        store_id: store_id,
        membership_role: StoreMembership.membership_roles[:admin]
      )
        session.delete(:current_store_id)
        redirect_to admin_stores_path, alert: "選択できない店舗です"
        return
      end

      session[:current_store_id] = store_id
      redirect_to admin_root_path, notice: "店舗を切り替えました"
    rescue ActionController::ParameterMissing
      redirect_to admin_stores_path, alert: "店舗を選択してください"
    end
  end
end
