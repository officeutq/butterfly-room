module Admin
  class BaseController < ApplicationController
    before_action -> { require_role!(:store_admin, :system_admin) }

    private

    def current_store
      return Store.first if current_user.system_admin?

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

      head :forbidden
    end
  end
end
