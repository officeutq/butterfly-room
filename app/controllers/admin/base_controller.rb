module Admin
  class BaseController < ApplicationController
    before_action -> { require_at_least!(:store_admin) }

    private

    def current_store
      # --- Current整合（booth優先）---
      # session[:current_booth_id] が有効なら store は booth.store を優先し、
      # session[:current_store_id] の不一致は補正する。
      #
      # 無効 booth（record不存在 / 権限的に無効）は session[:current_booth_id] をクリアする。
      #
      # ※ 07_モード導線設計.md の Current整合ルールに準拠
      if session[:current_booth_id].present?
        booth = Booth.find_by(id: session[:current_booth_id])

        if booth.blank?
          # record不存在
          session.delete(:current_booth_id)
        else
          allowed =
            if current_user.system_admin?
              true
            else
              # store_admin: 自分が admin membership を持つ store の booth のみ有効
              admin_membership_exists_for_store?(booth.store_id)
            end

          if allowed
            # booth優先で store を確定し、session不一致は補正
            session[:current_store_id] = booth.store_id if session[:current_store_id].to_i != booth.store_id
            return booth.store
          else
            # 権限的に無効（脱退/改ざん等）
            session.delete(:current_booth_id)
          end
        end
      end

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

      return membership&.store unless current_user.system_admin?

      # system_admin: session store が無い / 無効な場合の fallback
      Store.first
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
