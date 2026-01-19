module Admin
  class BaseController < ApplicationController
    before_action -> { require_role!(:store_admin, :system_admin) }

    private

    def current_store
      return @current_store if defined?(@current_store)

      membership =
        StoreMembership
          .includes(:store)
          .where(user_id: current_user.id, membership_role: StoreMembership.membership_roles[:admin])
          .order(:id)
          .first

      @current_store = membership&.store
    end
    helper_method :current_store

    def require_current_store!
      return if current_store.present?

      head :forbidden
    end
  end
end
