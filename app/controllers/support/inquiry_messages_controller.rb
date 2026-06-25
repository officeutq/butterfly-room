# frozen_string_literal: true

module Support
  class InquiryMessagesController < ApplicationController
    before_action :require_support_user!
    before_action :set_support_inquiry

    def create
      SupportInquiries::UserReplyService.new(
        user: current_user,
        support_inquiry: @support_inquiry,
        body: support_inquiry_message_params[:body]
      ).call

      redirect_to support_inquiry_path(@support_inquiry), notice: "返信を送信しました"
    rescue ActiveRecord::RecordInvalid => e
      @support_inquiry_message = e.record
      load_support_inquiry_messages
      render "support/inquiries/show", status: :unprocessable_entity
    rescue SupportInquiries::UserReplyService::NotAllowedError
      head :forbidden
    end

    private

    def require_support_user!
      return if current_user.customer? || current_user.cast? || current_user.store_admin?

      head :forbidden
    end

    def set_support_inquiry
      @support_inquiry =
        current_user
          .support_inquiries
          .includes(:store, :source_comment)
          .find(params[:inquiry_id])
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
