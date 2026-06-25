# frozen_string_literal: true

require "test_helper"

class SupportInquiryLifecycleTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    @customer = User.create!(email: "lifecycle_customer@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "lifecycle_other_customer@example.com", password: "password", role: :customer)
    @system_admin = User.create!(email: "lifecycle_system_admin@example.com", password: "password", role: :system_admin)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "customer and system admin can use support inquiry lifecycle" do
    sign_in @customer, scope: :user

    assert_difference -> { SupportInquiry.count }, +1 do
      assert_difference -> { SupportInquiryMessage.count }, +1 do
        assert_enqueued_emails 1 do
          post support_inquiries_path, params: create_params(subject: "Lifecycle inquiry")
        end
      end
    end

    support_inquiry = SupportInquiry.order(:id).last
    first_message = support_inquiry.support_inquiry_messages.order(:created_at, :id).first

    assert_redirected_to support_inquiry_path(support_inquiry)
    assert_equal "Lifecycle inquiry", support_inquiry.subject
    assert_not_nil first_message.email_enqueued_at

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Lifecycle initial message"

    get support_inquiries_path
    assert_response :success
    assert_includes response.body, "Lifecycle inquiry"

    sign_out :user
    sign_in @system_admin, scope: :user

    get system_admin_support_inquiries_path
    assert_response :success
    assert_includes response.body, "Lifecycle inquiry"

    get system_admin_support_inquiry_path(support_inquiry)
    assert_response :success
    assert_select "form[action=?]", system_admin_support_inquiry_messages_path(support_inquiry)

    assert_difference -> { SupportInquiryMessage.count }, +1 do
      assert_difference -> { Notification.count }, +1 do
        assert_enqueued_emails 1 do
          post system_admin_support_inquiry_messages_path(support_inquiry),
            params: reply_params("Lifecycle admin reply")
        end
      end
    end

    notification = Notification.order(:id).last
    admin_message = support_inquiry.support_inquiry_messages.order(:created_at, :id).last

    assert_redirected_to system_admin_support_inquiry_path(support_inquiry)
    assert_equal @customer, notification.recipient_user
    assert_equal "/support/inquiries/#{support_inquiry.id}", notification.link_path
    assert_not_nil admin_message.email_enqueued_at
    assert_predicate support_inquiry.reload, :last_message_sender_system_admin?

    sign_out :user
    sign_in @customer, scope: :user

    get notifications_path
    assert_response :success
    assert_includes response.body, notification.title

    assert_difference -> { NotificationRead.count }, +1 do
      get notification_path(notification)
    end

    assert_redirected_to support_inquiry_path(support_inquiry)

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Lifecycle admin reply"

    assert_difference -> { SupportInquiryMessage.count }, +1 do
      post support_inquiry_messages_path(support_inquiry),
        params: reply_params("Lifecycle customer follow up")
    end

    assert_redirected_to support_inquiry_path(support_inquiry)
    assert_predicate support_inquiry.reload, :last_message_sender_user?

    older_inquiry = create_inquiry_for(@other_customer, subject: "Older lifecycle inquiry")
    older_inquiry.update!(last_message_at: 2.days.ago)

    sign_out :user
    sign_in @system_admin, scope: :user

    get system_admin_support_inquiries_path

    assert_response :success
    assert_operator response.body.index("Lifecycle inquiry"), :<, response.body.index("Older lifecycle inquiry")
  end

  private

  def create_params(subject:)
    {
      support_inquiry: {
        category: "question",
        subject: subject,
        reply_email: "lifecycle-reply@example.com",
        body: "Lifecycle initial message"
      }
    }
  end

  def reply_params(body)
    {
      support_inquiry_message: {
        body: body
      }
    }
  end

  def create_inquiry_for(user, subject:)
    SupportInquiries::CreateService.new(
      user: user,
      attributes: {
        category: "question",
        subject: subject,
        reply_email: user.email
      },
      message_body: "Older lifecycle message"
    ).call.support_inquiry
  end
end
