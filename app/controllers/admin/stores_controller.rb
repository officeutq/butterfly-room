# frozen_string_literal: true

module Admin
  class StoresController < Admin::BaseController
    def index
      @stores =
        Store
          .joins(:store_memberships)
          .where(store_memberships: { user_id: current_user.id, membership_role: StoreMembership.membership_roles[:admin] })
          .distinct
          .order(:id)

      # 現在選択中があれば view で判定できるように
      @current_store_id = session[:current_store_id]
    end
  end
end
