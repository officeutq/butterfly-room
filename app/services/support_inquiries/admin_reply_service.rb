# frozen_string_literal: true

module SupportInquiries
  class AdminReplyService
    class NotAllowedError < StandardError; end

    NOTIFICATION_TITLE = "お問い合わせに返信がありました"
    NOTIFICATION_BODY = "運営からお問い合わせへの返信があります。"

    Result = Struct.new(:support_inquiry, :support_inquiry_message, :notification, keyword_init: true)

    def initialize(actor:, support_inquiry:, body:)
      @actor = actor
      @support_inquiry = support_inquiry
      @body = body
    end

    def call
      raise NotAllowedError unless @actor&.system_admin?

      support_inquiry_message = nil
      notification = nil

      ActiveRecord::Base.transaction do
        @support_inquiry.lock!

        support_inquiry_message = @support_inquiry.support_inquiry_messages.create!(
          sender_user: @actor,
          sender_kind: :system_admin,
          body: @body
        )

        @support_inquiry.update!(
          last_message_attributes(support_inquiry_message)
        )

        notification = create_notification!
      end

      enqueue_reply_mail!(support_inquiry_message)

      Result.new(
        support_inquiry: @support_inquiry,
        support_inquiry_message: support_inquiry_message,
        notification: notification
      )
    end

    private

    def last_message_attributes(support_inquiry_message)
      attributes = {
        last_message_at: support_inquiry_message.created_at,
        last_message_sender_kind: :system_admin
      }

      attributes[:status] = :in_progress if @support_inquiry.not_started?
      attributes
    end

    def create_notification!
      Notification.create!(
        title: NOTIFICATION_TITLE,
        body: NOTIFICATION_BODY,
        enabled: true,
        published_at: Time.current,
        created_by_user: @actor,
        recipient_user: @support_inquiry.user,
        link_path: Rails.application.routes.url_helpers.support_inquiry_path(@support_inquiry)
      )
    end

    def enqueue_reply_mail!(support_inquiry_message)
      SupportInquiryMailer
        .with(
          support_inquiry: @support_inquiry,
          support_inquiry_message: support_inquiry_message
        )
        .reply
        .deliver_later

      support_inquiry_message.update!(email_enqueued_at: Time.current)
    end
  end
end
