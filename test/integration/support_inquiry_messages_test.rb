# frozen_string_literal: true

require "test_helper"

class SupportInquiryMessagesTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "support_message_flow_customer@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "support_message_flow_other@example.com", password: "password", role: :customer)
    @system_admin = User.create!(email: "support_message_flow_admin@example.com", password: "password", role: :system_admin)
    @support_inquiry = create_inquiry_for(@customer, subject: "Thread subject")
  end

  test "show displays user reply form" do
    sign_in @customer, scope: :user

    get support_inquiry_path(@support_inquiry)

    assert_response :success
    assert_select "form[action=?]", support_inquiry_messages_path(@support_inquiry)
    assert_select "textarea[name='support_inquiry_message[body]']"
  end

  test "owner can reply and see reply in message history" do
    sign_in @customer, scope: :user

    assert_difference -> { SupportInquiryMessage.count }, +1 do
      post support_inquiry_messages_path(@support_inquiry), params: reply_params(body: "User reply body")
    end

    assert_redirected_to support_inquiry_path(@support_inquiry)

    @support_inquiry.reload
    message = @support_inquiry.support_inquiry_messages.order(:created_at, :id).last

    assert_equal "User reply body", message.body
    assert_equal @customer, message.sender_user
    assert_equal "user", message.sender_kind
    assert_equal "user", @support_inquiry.last_message_sender_kind
    assert_equal message.created_at.to_f, @support_inquiry.last_message_at.to_f

    follow_redirect!
    assert_response :success
    assert_includes response.body, "User reply body"
  end

  test "resolved inquiry returns to in progress after owner reply" do
    @support_inquiry.update!(
      status: :resolved,
      resolved_at: 1.hour.ago,
      last_message_sender_kind: :system_admin
    )

    sign_in @customer, scope: :user

    post support_inquiry_messages_path(@support_inquiry), params: reply_params(body: "Reopen reply")

    assert_redirected_to support_inquiry_path(@support_inquiry)
    @support_inquiry.reload

    assert_predicate @support_inquiry, :in_progress?
    assert_nil @support_inquiry.resolved_at
    assert_predicate @support_inquiry, :last_message_sender_user?
  end

  test "other user cannot reply to another users inquiry" do
    sign_in @other_customer, scope: :user

    assert_no_difference -> { SupportInquiryMessage.count } do
      post support_inquiry_messages_path(@support_inquiry), params: reply_params(body: "Other reply")
    end

    assert_response :not_found
  end

  test "guest is redirected to login" do
    post support_inquiry_messages_path(@support_inquiry), params: reply_params(body: "Guest reply")

    assert_redirected_to new_user_session_path
  end

  test "system admin cannot reply from user side" do
    sign_in @system_admin, scope: :user

    assert_no_difference -> { SupportInquiryMessage.count } do
      post support_inquiry_messages_path(@support_inquiry), params: reply_params(body: "Admin reply")
    end

    assert_response :forbidden
  end

  test "body is required" do
    sign_in @customer, scope: :user

    assert_no_difference -> { SupportInquiryMessage.count } do
      post support_inquiry_messages_path(@support_inquiry), params: reply_params(body: "")
    end

    assert_response :unprocessable_entity
    assert_select "textarea[name='support_inquiry_message[body]']"
  end

  test "body maximum length is enforced" do
    sign_in @customer, scope: :user

    assert_no_difference -> { SupportInquiryMessage.count } do
      post support_inquiry_messages_path(@support_inquiry), params: reply_params(
        body: "a" * (SupportInquiryMessage::BODY_MAX_LENGTH + 1)
      )
    end

    assert_response :unprocessable_entity
  end

  private

  def reply_params(body:)
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
      message_body: "Initial message"
    ).call.support_inquiry
  end
end
