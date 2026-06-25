# frozen_string_literal: true

require "test_helper"

class SupportInquiries::AdminReplyServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    @customer = User.create!(email: "admin_reply_customer@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "admin_reply_other@example.com", password: "password", role: :customer)
    @system_admin = User.create!(email: "admin_reply_system@example.com", password: "password", role: :system_admin)
    @store_admin = User.create!(email: "admin_reply_store@example.com", password: "password", role: :store_admin)
    @support_inquiry = create_inquiry_for(@customer)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "system admin reply creates message notification and enqueues mail" do
    result = nil

    assert_difference -> { SupportInquiryMessage.count }, +1 do
      assert_difference -> { Notification.count }, +1 do
        assert_enqueued_emails 1 do
          result = SupportInquiries::AdminReplyService.new(
            actor: @system_admin,
            support_inquiry: @support_inquiry,
            body: "Admin reply body"
          ).call
        end
      end
    end

    @support_inquiry.reload
    message = result.support_inquiry_message.reload
    notification = result.notification

    assert_equal @support_inquiry, result.support_inquiry
    assert_equal @system_admin, message.sender_user
    assert_equal "system_admin", message.sender_kind
    assert_equal "Admin reply body", message.body
    assert_not_nil message.email_enqueued_at
    assert_equal "system_admin", @support_inquiry.last_message_sender_kind
    assert_equal message.created_at.to_f, @support_inquiry.last_message_at.to_f
    assert_predicate @support_inquiry, :in_progress?

    assert_equal "お問い合わせに返信がありました", notification.title
    assert_equal "運営からお問い合わせへの返信があります。", notification.body
    assert_equal @system_admin, notification.created_by_user
    assert_equal @customer, notification.recipient_user
    assert_equal "/support/inquiries/#{@support_inquiry.id}", notification.link_path
    assert_includes Notification.visible_to(@customer), notification
    assert_not_includes Notification.visible_to(@other_customer), notification
  end

  test "resolved inquiry remains resolved when system admin replies" do
    resolved_at = 1.hour.ago
    @support_inquiry.update!(
      status: :resolved,
      resolved_at: resolved_at,
      last_message_sender_kind: :user
    )

    SupportInquiries::AdminReplyService.new(
      actor: @system_admin,
      support_inquiry: @support_inquiry,
      body: "Resolved follow up"
    ).call

    @support_inquiry.reload

    assert_predicate @support_inquiry, :resolved?
    assert_equal resolved_at.to_i, @support_inquiry.resolved_at.to_i
    assert_predicate @support_inquiry, :last_message_sender_system_admin?
  end

  test "non system admin cannot reply" do
    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_no_difference -> { Notification.count } do
        assert_no_enqueued_emails do
          assert_raises(SupportInquiries::AdminReplyService::NotAllowedError) do
            SupportInquiries::AdminReplyService.new(
              actor: @store_admin,
              support_inquiry: @support_inquiry,
              body: "Store admin reply"
            ).call
          end
        end
      end
    end
  end

  test "body is required" do
    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_no_difference -> { Notification.count } do
        assert_no_enqueued_emails do
          assert_raises(ActiveRecord::RecordInvalid) do
            SupportInquiries::AdminReplyService.new(
              actor: @system_admin,
              support_inquiry: @support_inquiry,
              body: ""
            ).call
          end
        end
      end
    end
  end

  private

  def create_inquiry_for(user)
    SupportInquiries::CreateService.new(
      user: user,
      attributes: {
        category: "question",
        subject: "Need admin help",
        reply_email: user.email
      },
      message_body: "Initial message"
    ).call.support_inquiry
  end
end
