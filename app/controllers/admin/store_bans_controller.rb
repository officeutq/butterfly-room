# frozen_string_literal: true

module Admin
  class StoreBansController < Admin::BaseController
    before_action -> { require_at_least!(:system_admin) }
    before_action :require_current_store!

    def index
      @store_bans =
        current_store.store_bans
          .includes(:customer_user, :created_by_store_admin_user, :revoked_by_user, :source_comment)
          .order(Arel.sql("CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END ASC"), id: :desc)

      @store_ban = current_store.store_bans.new
      load_customer_options
    end

    def create
      customer_user = User.find_by(id: store_ban_params[:customer_user_id])

      result =
        Admin::StoreBans::CreateService.new(
          store: current_store,
          customer_user: customer_user,
          actor: current_user,
          reason: store_ban_params[:reason]
        ).call

      notice = result.created ? "BANしました" : "既にBAN済みです"
      redirect_back fallback_location: admin_store_bans_path, notice: notice
    rescue Admin::StoreBans::CreateService::UnsupportedCustomerError
      redirect_back fallback_location: admin_store_bans_path, alert: "BAN対象はcustomerのみ指定できます"
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: admin_store_bans_path, alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      ban = current_store.store_bans.find(params[:id])
      result =
        Admin::StoreBans::RevokeService.new(
          store_ban: ban,
          actor: current_user,
          reason: params[:revocation_reason]
        ).call

      notice = result.revoked ? "BAN解除しました" : "既にBAN解除済みです"
      redirect_back fallback_location: admin_store_bans_path, notice: notice
    end

    private

    def store_ban_params
      params.require(:store_ban).permit(:customer_user_id, :reason)
    end

    def load_customer_options
      @customer_options =
        User
          .customer
          .order(:id)
          .map { |user| [ customer_option_label(user), user.id ] }
    end

    def customer_option_label(user)
      name = user.display_name.presence || "no name"
      "##{user.id} #{name} / #{user.email}"
    end
  end
end
