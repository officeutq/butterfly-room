# frozen_string_literal: true

module Admin
  class CastsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @cast_memberships =
        StoreMembership
          .includes(:user)
          .where(store_id: current_store.id, membership_role: :cast)
          .order(:id)

      existing_user_ids = @cast_memberships.map(&:user_id)

      @candidate_cast_users =
        User
          .where(role: User.roles[:cast])
          .where.not(id: existing_user_ids)
          .order(:id)

      @store_membership = StoreMembership.new
    end

    def create
      user_id = params.require(:store_membership).permit(:user_id)[:user_id]
      user = User.find(user_id)

      unless user.cast?
        redirect_to admin_casts_path, alert: "castユーザーのみ追加できます"
        return
      end

      StoreMembership.create!(
        store_id: current_store.id,
        user_id: user.id,
        membership_role: :cast
      )

      redirect_to admin_casts_path, notice: "キャストを登録しました"
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_casts_path, alert: "ユーザーが見つかりません"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_casts_path, alert: e.record.errors.full_messages.join(", ")
    rescue ActiveRecord::RecordNotUnique
      redirect_to admin_casts_path, alert: "すでに登録されています"
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
