module Admin
  class BaseController < ApplicationController
    before_action -> { require_at_least!(:store_admin) }

    private

    def current_store
      return Store.first if current_user.system_admin?

      # 1) session 優先
      if session[:current_store_id].present?
        store = Store.find_by(id: session[:current_store_id])
        if store.present? && admin_membership_exists_for_store?(store.id)
          return store
        end

        # 改ざん/脱退/削除 への耐性：不正ならクリア
        session.delete(:current_store_id)
      end

      # 2) fallback: 従来通り「最初の admin membership」
      membership =
        StoreMembership
          .includes(:store)
          .where(user_id: current_user.id, membership_role: :admin)
          .order(:id)
          .first

      membership&.store
    end

    helper_method :current_store

    def require_current_store!
      return if current_user.system_admin?
      return if current_store.present?

      redirect_to admin_stores_path, alert: "操作対象の店舗を選択してください"
    end

    def admin_membership_exists_for_store?(store_id)
      StoreMembership.exists?(
        user_id: current_user.id,
        store_id: store_id,
        membership_role: StoreMembership.membership_roles[:admin]
      )
    end
  end
end
