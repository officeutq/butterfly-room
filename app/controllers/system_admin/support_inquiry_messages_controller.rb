# frozen_string_literal: true

module SystemAdmin
  class SupportInquiryMessagesController < SystemAdmin::BaseController
    before_action :set_support_inquiry

    def create
      SupportInquiries::AdminReplyService.new(
        actor: current_user,
        support_inquiry: @support_inquiry,
        body: support_inquiry_message_params[:body]
      ).call

      redirect_to system_admin_support_inquiry_path(@support_inquiry), notice: "返信を送信しました"
    rescue ActiveRecord::RecordInvalid => e
      @support_inquiry_message =
        if e.record.is_a?(SupportInquiryMessage)
          e.record
        else
          @support_inquiry.support_inquiry_messages.build(body: support_inquiry_message_params[:body])
        end
      load_support_inquiry_messages
      render "system_admin/support_inquiries/show", status: :unprocessable_entity
    rescue SupportInquiries::AdminReplyService::NotAllowedError
      head :forbidden
    end

    private

    def set_support_inquiry
      @support_inquiry =
        SupportInquiry
          .includes(:user, :store, :source_comment)
          .find(params[:support_inquiry_id])
    end

    def load_support_inquiry_messages
      @support_inquiry_messages =
        @support_inquiry
          .support_inquiry_messages
          .includes(:sender_user)
    end

    def support_inquiry_message_params
      params.require(:support_inquiry_message).permit(:body)
    end
  end
end
