# frozen_string_literal: true

require "test_helper"

class SystemAdminSupportInquiryMessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    @customer = User.create!(email: "system_admin_reply_customer@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "system_admin_reply_other@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "system_admin_reply_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "system_admin_reply_store@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "system_admin_reply_system@example.com", password: "password", role: :system_admin)
    @support_inquiry = create_inquiry_for(@customer)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "show displays system admin reply form" do
    sign_in @system_admin, scope: :user

    get system_admin_support_inquiry_path(@support_inquiry)

    assert_response :success
    assert_select "form[action=?]", system_admin_support_inquiry_messages_path(@support_inquiry)
    assert_select "textarea[name='support_inquiry_message[body]']"
  end

  test "system admin can reply and notify inquiry owner" do
    sign_in @system_admin, scope: :user

    assert_difference -> { SupportInquiryMessage.count }, +1 do
      assert_difference -> { Notification.count }, +1 do
        assert_enqueued_emails 1 do
          post system_admin_support_inquiry_messages_path(@support_inquiry), params: reply_params("Admin integration reply")
        end
      end
    end

    assert_redirected_to system_admin_support_inquiry_path(@support_inquiry)

    @support_inquiry.reload
    message = @support_inquiry.support_inquiry_messages.order(:created_at, :id).last
    notification = Notification.order(:id).last

    assert_equal "Admin integration reply", message.body
    assert_equal @system_admin, message.sender_user
    assert_predicate message, :sender_system_admin?
    assert_not_nil message.email_enqueued_at
    assert_predicate @support_inquiry, :last_message_sender_system_admin?
    assert_predicate @support_inquiry, :in_progress?

    assert_equal @customer, notification.recipient_user
    assert_equal @system_admin, notification.created_by_user
    assert_equal "/support/inquiries/#{@support_inquiry.id}", notification.link_path

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Admin integration reply"
  end

  test "reply notification is visible only to inquiry owner and links to inquiry detail" do
    sign_in @system_admin, scope: :user

    post system_admin_support_inquiry_messages_path(@support_inquiry), params: reply_params("Linked notification reply")
    notification = Notification.order(:id).last

    sign_out :user
    sign_in @other_customer, scope: :user

    get notifications_path
    assert_response :success
    assert_not_includes response.body, notification.title

    get notification_path(notification)
    assert_response :not_found

    sign_out :user
    sign_in @customer, scope: :user

    get notifications_path
    assert_response :success
    assert_includes response.body, notification.title

    assert_difference -> { NotificationRead.count }, +1 do
      get notification_path(notification)
    end

    assert_redirected_to support_inquiry_path(@support_inquiry)

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Linked notification reply"
  end

  test "guest is redirected to login" do
    assert_no_difference -> { SupportInquiryMessage.count } do
      post system_admin_support_inquiry_messages_path(@support_inquiry), params: reply_params("Guest reply")
    end

    assert_redirected_to new_user_session_path
  end

  test "non system admins cannot reply" do
    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      assert_no_difference -> { SupportInquiryMessage.count } do
        assert_no_difference -> { Notification.count } do
          post system_admin_support_inquiry_messages_path(@support_inquiry), params: reply_params("Forbidden reply")
        end
      end

      assert_response :forbidden
      sign_out :user
    end
  end

  test "body is required" do
    sign_in @system_admin, scope: :user

    assert_no_difference -> { SupportInquiryMessage.count } do
      assert_no_difference -> { Notification.count } do
        assert_no_enqueued_emails do
          post system_admin_support_inquiry_messages_path(@support_inquiry), params: reply_params("")
        end
      end
    end

    assert_response :unprocessable_entity
    assert_select "textarea[name='support_inquiry_message[body]']"
  end

  private

  def reply_params(body)
    {
      support_inquiry_message: {
        body: body
      }
    }
  end

  def create_inquiry_for(user)
    SupportInquiries::CreateService.new(
      user: user,
      attributes: {
        category: "question",
        subject: "Need admin reply",
        reply_email: user.email
      },
      message_body: "Initial message"
    ).call.support_inquiry
  end
end
