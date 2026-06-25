# frozen_string_literal: true

module SupportInquiries
  class UserReplyService
    class NotAllowedError < StandardError; end

    Result = Struct.new(:support_inquiry, :support_inquiry_message, keyword_init: true)

    def initialize(user:, support_inquiry:, body:)
      @user = user
      @support_inquiry = support_inquiry
      @body = body
    end

    def call
      raise NotAllowedError unless allowed?

      support_inquiry_message = nil

      ActiveRecord::Base.transaction do
        @support_inquiry.lock!

        support_inquiry_message = @support_inquiry.support_inquiry_messages.create!(
          sender_user: @user,
          sender_kind: :user,
          body: @body
        )

        @support_inquiry.update!(
          last_message_attributes(support_inquiry_message)
        )
      end

      Result.new(
        support_inquiry: @support_inquiry,
        support_inquiry_message: support_inquiry_message
      )
    end

    private

    def allowed?
      support_user? && @support_inquiry.user_id == @user.id
    end

    def support_user?
      @user&.customer? || @user&.cast? || @user&.store_admin?
    end

    def last_message_attributes(support_inquiry_message)
      attributes = {
        last_message_at: support_inquiry_message.created_at,
        last_message_sender_kind: :user
      }

      if @support_inquiry.resolved?
        attributes[:status] = :in_progress
        attributes[:resolved_at] = nil
      end

      attributes
    end
  end
end
