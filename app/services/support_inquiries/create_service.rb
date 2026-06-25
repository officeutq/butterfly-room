# frozen_string_literal: true

module SupportInquiries
  class CreateService
    class NotAllowedError < StandardError; end

    Result = Struct.new(:support_inquiry, :support_inquiry_message, keyword_init: true)

    def initialize(user:, attributes:, message_body:, store: nil, source_comment: nil)
      @user = user
      @attributes = attributes.to_h.symbolize_keys
      @message_body = message_body
      @store = store
      @source_comment = source_comment
    end

    def call
      raise NotAllowedError unless support_user?
      raise NotAllowedError unless source_comment_allowed?

      support_inquiry = build_support_inquiry
      support_inquiry_message = build_support_inquiry_message(support_inquiry)

      ActiveRecord::Base.transaction do
        validate_records!(support_inquiry, support_inquiry_message)

        support_inquiry.save!
        support_inquiry_message.save!
      end

      Result.new(
        support_inquiry: support_inquiry,
        support_inquiry_message: support_inquiry_message
      )
    end

    private

    def support_user?
      @user&.customer? || @user&.cast? || @user&.store_admin?
    end

    def source_comment_allowed?
      return true if @source_comment.blank?
      return false unless @user&.store_admin?
      return false if @store.blank?
      return false unless @user.admin_of_store?(@store.id)

      @source_comment.stream_session&.store_id == @store.id
    end

    def build_support_inquiry
      now = Time.current

      SupportInquiry.new(
        user: @user,
        store: @store,
        category: @attributes[:category],
        status: :not_started,
        subject: @attributes[:subject],
        reply_email: @attributes[:reply_email],
        name_snapshot: name_snapshot,
        role_snapshot: @user.role,
        store_name_snapshot: @store&.name,
        source_comment: @source_comment,
        last_message_at: now,
        last_message_sender_kind: :user
      )
    end

    def build_support_inquiry_message(support_inquiry)
      support_inquiry.support_inquiry_messages.build(
        sender_user: @user,
        sender_kind: :user,
        body: @message_body
      )
    end

    def validate_records!(support_inquiry, support_inquiry_message)
      support_inquiry_valid = support_inquiry.valid?
      message_valid = support_inquiry_message.valid?

      unless message_valid
        support_inquiry_message.errors.full_messages.each do |message|
          support_inquiry.errors.add(:base, message)
        end
      end

      raise ActiveRecord::RecordInvalid, support_inquiry unless support_inquiry_valid && message_valid
    end

    def name_snapshot
      @user.display_name.presence || @user.email
    end
  end
end
