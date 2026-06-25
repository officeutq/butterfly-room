# frozen_string_literal: true

require "test_helper"

class SupportInquiries::CreateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    @store = Store.create!(name: "Support Service Store")
    @other_store = Store.create!(name: "Other Support Service Store")
    @customer = User.create!(
      email: "support_service_customer@example.com",
      password: "password",
      role: :customer,
      display_name: "Support Customer"
    )
    @store_admin = User.create!(
      email: "support_service_store_admin@example.com",
      password: "password",
      role: :store_admin,
      display_name: "Support Store Admin"
    )
    @system_admin = User.create!(
      email: "support_service_system_admin@example.com",
      password: "password",
      role: :system_admin
    )
    @cast = User.create!(email: "support_service_cast@example.com", password: "password", role: :cast)

    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)

    @source_comment = create_comment_for(@store, body: "source comment")
    @other_store_comment = create_comment_for(@other_store, body: "other store source comment")
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "creates inquiry and first message with snapshots" do
    result = nil

    assert_difference -> { SupportInquiry.count }, +1 do
      assert_difference -> { SupportInquiryMessage.count }, +1 do
        assert_enqueued_emails 1 do
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
    assert_not_nil message.email_enqueued_at
  end

  test "rejects system admin users" do
    assert_no_enqueued_emails do
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
  end

  test "store admin can create inquiry with source comment for own store" do
    result = nil

    assert_difference -> { SupportInquiry.count }, +1 do
      assert_difference -> { SupportInquiryMessage.count }, +1 do
        result = SupportInquiries::CreateService.new(
          user: @store_admin,
          store: @store,
          source_comment: @source_comment,
          attributes: {
            category: "report",
            subject: "通報に関する運営報告",
            reply_email: "store-admin-reply@example.com"
          },
          message_body: "Please review this report"
        ).call
      end
    end

    assert_equal @source_comment, result.support_inquiry.source_comment
    assert_equal @store, result.support_inquiry.store
    assert_equal "store_admin", result.support_inquiry.role_snapshot
  end

  test "rejects source comment when user is not store admin" do
    assert_no_enqueued_emails do
      assert_no_difference -> { SupportInquiry.count } do
        assert_no_difference -> { SupportInquiryMessage.count } do
          assert_raises(SupportInquiries::CreateService::NotAllowedError) do
            SupportInquiries::CreateService.new(
              user: @customer,
              store: @store,
              source_comment: @source_comment,
              attributes: {
                category: "report",
                subject: "通報に関する運営報告",
                reply_email: "reply@example.com"
              },
              message_body: "Please review"
            ).call
          end
        end
      end
    end
  end

  test "rejects source comment outside store admin store" do
    assert_no_enqueued_emails do
      assert_no_difference -> { SupportInquiry.count } do
        assert_no_difference -> { SupportInquiryMessage.count } do
          assert_raises(SupportInquiries::CreateService::NotAllowedError) do
            SupportInquiries::CreateService.new(
              user: @store_admin,
              store: @store,
              source_comment: @other_store_comment,
              attributes: {
                category: "report",
                subject: "通報に関する運営報告",
                reply_email: "reply@example.com"
              },
              message_body: "Please review"
            ).call
          end
        end
      end
    end
  end

  test "rolls back inquiry when first message is invalid" do
    assert_no_enqueued_emails do
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

  private

  def create_comment_for(store, body:)
    booth = Booth.create!(store: store, name: "#{store.name} Booth", status: :offline)
    stream_session = StreamSession.create!(
      store: store,
      booth: booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      title: "#{store.name} Stream"
    )

    Comment.create!(
      stream_session: stream_session,
      booth: booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: body,
      metadata: {}
    )
  end
end
