# frozen_string_literal: true

module SystemAdmin
  class SupportInquiriesController < SystemAdmin::BaseController
    before_action :set_support_inquiry, only: %i[show update]

    def index
      @status_options = SupportInquiry.statuses.keys
      @category_options = SupportInquiry.categories.keys
      @role_options = User.roles.keys

      @support_inquiries =
        filtered_support_inquiries
          .includes(:user, :store, :source_comment)
          .order(last_message_at: :desc, id: :desc)
    end

    def show
      load_support_inquiry_messages
      build_support_inquiry_message
    end

    def update
      SupportInquiries::UpdateStatusService.new(
        actor: current_user,
        support_inquiry: @support_inquiry,
        status: support_inquiry_params[:status]
      ).call

      redirect_to system_admin_support_inquiry_path(@support_inquiry), notice: "状態を更新しました"
    rescue SupportInquiries::UpdateStatusService::InvalidStatusError, ActiveRecord::RecordInvalid => e
      @support_inquiry.errors.add(:base, e.message)
      load_support_inquiry_messages
      build_support_inquiry_message
      render :show, status: :unprocessable_entity
    end

    private

    def set_support_inquiry
      @support_inquiry =
        SupportInquiry
          .includes(:user, :store, :source_comment)
          .find(params[:id])
    end

    def load_support_inquiry_messages
      @support_inquiry_messages =
        @support_inquiry
          .support_inquiry_messages
          .includes(:sender_user)
    end

    def build_support_inquiry_message
      @support_inquiry_message ||= @support_inquiry.support_inquiry_messages.build
    end

    def filtered_support_inquiries
      scope = SupportInquiry.all
      scope = scope.where(status: params[:status]) if SupportInquiry.statuses.key?(params[:status].to_s)
      scope = scope.where(category: params[:category]) if SupportInquiry.categories.key?(params[:category].to_s)
      scope = scope.where(role_snapshot: params[:role_snapshot]) if User.roles.key?(params[:role_snapshot].to_s)
      scope
    end

    def support_inquiry_params
      params.require(:support_inquiry).permit(:status)
    end
  end
end
