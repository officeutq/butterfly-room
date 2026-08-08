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

      result = StoreMemberships::RemoveCastService.new(
        membership:,
        actor: current_user
      ).call!

      notice =
        if result.archived_booths_count.positive?
          "キャスト登録を解除し、関連ブース#{result.archived_booths_count}件をアーカイブしました"
        else
          "キャスト登録を解除しました"
        end

      redirect_to admin_casts_path, notice:
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue StoreMemberships::RemoveCastService::NotAuthorized,
           StreamSessions::EndService::NotAuthorized
      head :forbidden
    rescue StandardError => e
      redirect_to admin_casts_path, alert: e.message
    end
  end
end
