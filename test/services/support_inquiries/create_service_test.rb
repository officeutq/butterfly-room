# frozen_string_literal: true

require "test_helper"

class SupportInquiries::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Support Service Store")
    @customer = User.create!(
      email: "support_service_customer@example.com",
      password: "password",
      role: :customer,
      display_name: "Support Customer"
    )
    @system_admin = User.create!(
      email: "support_service_system_admin@example.com",
      password: "password",
      role: :system_admin
    )
  end

  test "creates inquiry and first message with snapshots" do
    result = nil

    assert_difference -> { SupportInquiry.count }, +1 do
      assert_difference -> { SupportInquiryMessage.count }, +1 do
        result = SupportInquiries::CreateService.new(
          user: @customer,
          store: @store,
          attributes: {
            category: "question",
            subject: "Need help",
            reply_email: "reply@example.com"
          },
          message_body: "Please help"
        ).call
      end
    end

    inquiry = result.support_inquiry
    message = result.support_inquiry_message

    assert_equal @customer, inquiry.user
    assert_equal @store, inquiry.store
    assert_equal "question", inquiry.category
    assert_equal "not_started", inquiry.status
    assert_equal "Need help", inquiry.subject
    assert_equal "reply@example.com", inquiry.reply_email
    assert_equal "Support Customer", inquiry.name_snapshot
    assert_equal "customer", inquiry.role_snapshot
    assert_equal @store.name, inquiry.store_name_snapshot
    assert_equal "user", inquiry.last_message_sender_kind
    assert_equal "Please help", message.body
    assert_equal @customer, message.sender_user
    assert_equal "user", message.sender_kind
  end

  test "rejects system admin users" do
    assert_no_difference -> { SupportInquiry.count } do
      assert_no_difference -> { SupportInquiryMessage.count } do
        assert_raises(SupportInquiries::CreateService::NotAllowedError) do
          SupportInquiries::CreateService.new(
            user: @system_admin,
            attributes: {
              category: "question",
              subject: "Need help",
              reply_email: "reply@example.com"
            },
            message_body: "Please help"
          ).call
        end
      end
    end
  end

  test "rolls back inquiry when first message is invalid" do
    assert_no_difference -> { SupportInquiry.count } do
      assert_no_difference -> { SupportInquiryMessage.count } do
        assert_raises(ActiveRecord::RecordInvalid) do
          SupportInquiries::CreateService.new(
            user: @customer,
            attributes: {
              category: "question",
              subject: "Need help",
              reply_email: "reply@example.com"
            },
            message_body: ""
          ).call
        end
      end
    end
  end
end
