# frozen_string_literal: true

module Admin
  class StoreBansController < Admin::BaseController
    before_action :require_current_store!

    def index
      @store_bans =
        current_store.store_bans
          .includes(:customer_user)
          .order(id: :desc)

      @store_ban = current_store.store_bans.new
    end

    def create
      ban = current_store.store_bans.new(store_ban_params)
      ban.created_by_store_admin_user = current_user

      if ban.save
        redirect_back fallback_location: admin_store_bans_path, notice: "BANしました"
      else
        redirect_back fallback_location: admin_store_bans_path, alert: ban.errors.full_messages.to_sentence
      end
    end

    def destroy
      ban = current_store.store_bans.find(params[:id])
      ban.destroy!
      redirect_back fallback_location: admin_store_bans_path, notice: "BAN解除しました"
    end

    private

    def store_ban_params
      params.require(:store_ban).permit(:customer_user_id, :reason)
    end
  end
end
