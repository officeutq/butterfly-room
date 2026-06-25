# frozen_string_literal: true

require "test_helper"

class SupportInquiries::UserReplyServiceTest < ActiveSupport::TestCase
  setup do
    @customer = User.create!(email: "support_reply_customer@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "support_reply_other@example.com", password: "password", role: :customer)
    @system_admin = User.create!(email: "support_reply_admin@example.com", password: "password", role: :system_admin)
    @support_inquiry = create_inquiry_for(@customer)
  end

  test "owner can add reply message and update last message metadata" do
    previous_last_message_at = @support_inquiry.last_message_at
    result = nil

    assert_difference -> { SupportInquiryMessage.count }, +1 do
      result = SupportInquiries::UserReplyService.new(
        user: @customer,
        support_inquiry: @support_inquiry,
        body: "Reply body"
      ).call
    end

    @support_inquiry.reload
    message = result.support_inquiry_message

    assert_equal @support_inquiry, result.support_inquiry
    assert_equal @customer, message.sender_user
    assert_equal "user", message.sender_kind
    assert_equal "Reply body", message.body
    assert_equal "user", @support_inquiry.last_message_sender_kind
    assert_equal message.created_at.to_f, @support_inquiry.last_message_at.to_f
    assert_operator @support_inquiry.last_message_at, :>=, previous_last_message_at
  end

  test "resolved inquiry returns to in progress when owner replies" do
    @support_inquiry.update!(
      status: :resolved,
      resolved_at: 1.hour.ago,
      last_message_sender_kind: :system_admin
    )

    SupportInquiries::UserReplyService.new(
      user: @customer,
      support_inquiry: @support_inquiry,
      body: "Reopen"
    ).call

    @support_inquiry.reload

    assert_predicate @support_inquiry, :in_progress?
    assert_nil @support_inquiry.resolved_at
    assert_predicate @support_inquiry, :last_message_sender_user?
  end

  test "other users cannot reply" do
    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_raises(SupportInquiries::UserReplyService::NotAllowedError) do
        SupportInquiries::UserReplyService.new(
          user: @other_customer,
          support_inquiry: @support_inquiry,
          body: "Other reply"
        ).call
      end
    end
  end

  test "system admin cannot reply from user reply service" do
    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_raises(SupportInquiries::UserReplyService::NotAllowedError) do
        SupportInquiries::UserReplyService.new(
          user: @system_admin,
          support_inquiry: @support_inquiry,
          body: "Admin reply"
        ).call
      end
    end
  end

  test "body is required" do
    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        SupportInquiries::UserReplyService.new(
          user: @customer,
          support_inquiry: @support_inquiry,
          body: ""
        ).call
      end
    end
  end

  test "body maximum length is enforced" do
    assert_difference -> { SupportInquiryMessage.count }, +1 do
      SupportInquiries::UserReplyService.new(
        user: @customer,
        support_inquiry: @support_inquiry,
        body: "a" * SupportInquiryMessage::BODY_MAX_LENGTH
      ).call
    end

    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        SupportInquiries::UserReplyService.new(
          user: @customer,
          support_inquiry: @support_inquiry,
          body: "a" * (SupportInquiryMessage::BODY_MAX_LENGTH + 1)
        ).call
      end
    end
  end

  private

  def create_inquiry_for(user)
    SupportInquiries::CreateService.new(
      user: user,
      attributes: {
        category: "question",
        subject: "Need help",
        reply_email: user.email
      },
      message_body: "Initial message"
    ).call.support_inquiry
  end
end
