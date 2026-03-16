# frozen_string_literal: true

module Admin
  class StoresController < Admin::BaseController
    include RemovableImageAttachment

    before_action :set_store, only: %i[edit update]
    before_action :authorize_store_edit!, only: %i[edit update]

    def index
      @stores =
        if current_user.system_admin?
          Store.order(:id)
        else
          Store
            .joins(:store_memberships)
            .where(store_memberships: { user_id: current_user.id, membership_role: StoreMembership.membership_roles[:admin] })
            .distinct
            .order(:id)
        end

      @current_store_id = session[:current_store_id]
      @return_to = params[:return_to].presence
      @return_to_key = params[:return_to_key].presence
    end

    def edit
    end

    def update
      if @store.update(store_params)
        purge_attachment_if_requested(
          record: @store,
          attachment_name: :thumbnail,
          remove_param_name: :remove_thumbnail
        )

        redirect_to edit_admin_store_path(@store), notice: "店舗情報を更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_store
      @store = Store.find(params[:id])
    end

    def authorize_store_edit!
      return if current_user.system_admin?

      ok = StoreMembership.admin_only.exists?(user_id: current_user.id, store_id: @store.id)
      head :forbidden unless ok
    end

    def store_params
      params.require(:store).permit(
        :name,
        :description,
        :area,
        :business_type,
        :thumbnail
      )
    end
  end
end
