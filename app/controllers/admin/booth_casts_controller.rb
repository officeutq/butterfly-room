# frozen_string_literal: true

module Admin
  class BoothCastsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @booths =
        current_store
          .booths
          .includes(booth_casts: :cast_user)
          .order(id: :desc)

      @cast_memberships =
        StoreMembership
          .includes(:user)
          .where(store_id: current_store.id, membership_role: :cast)
          .order(:id)
    end

    def create
      booth_id = booth_cast_params[:booth_id]
      cast_user_id = booth_cast_params[:cast_user_id]

      booth = current_store.booths.find(booth_id)

      if booth.archived?
        redirect_to resolved_return_to, alert: "アーカイブ済みブースには紐づけできません"
        return
      end

      if booth.booth_casts.exists?
        redirect_to resolved_return_to, alert: "このブースには既にキャストが紐づいています（Phase1では差し替えできません）"
        return
      end

      unless StoreMembership.exists?(store_id: current_store.id, membership_role: :cast, user_id: cast_user_id)
        redirect_to resolved_return_to, alert: "選択できないキャストです"
        return
      end

      BoothCast.create!(booth: booth, cast_user_id: cast_user_id)

      redirect_to resolved_return_to, notice: "キャストを紐づけました"
    rescue ActionController::ParameterMissing
      redirect_to resolved_return_to, alert: "パラメータが不正です"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue ActiveRecord::RecordInvalid => e
      redirect_to resolved_return_to, alert: e.record.errors.full_messages.join(", ")
    end

    private

    def booth_cast_params
      params.require(:booth_cast).permit(:booth_id, :cast_user_id)
    end

    def resolved_return_to
      path = params[:return_to].to_s

      return admin_booths_path if path.blank?
      return admin_booths_path unless path.start_with?("/")
      return admin_booths_path if path.start_with?("//")
      return admin_booths_path if path.include?("\n") || path.include?("\r")
      return admin_booths_path if path.include?("\0")

      path
    end
  end
end
