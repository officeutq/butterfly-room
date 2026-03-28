# frozen_string_literal: true

module Admin
  class CastsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @cast_memberships =
        StoreMembership
          .includes(user: { booth_casts: :booth })
          .where(store_id: current_store.id, membership_role: :cast)
          .order(:id)
    end

    def destroy
      membership =
        StoreMembership
          .where(store_id: current_store.id, membership_role: :cast)
          .find(params[:id])

      membership.destroy!

      redirect_to admin_casts_path, notice: "キャスト登録を解除しました"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
