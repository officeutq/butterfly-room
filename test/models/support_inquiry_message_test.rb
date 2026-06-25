# frozen_string_literal: true

require "test_helper"

class SupportInquiryMessageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "support_message_user@example.com", password: "password", role: :customer)
    @system_admin = User.create!(email: "support_message_admin@example.com", password: "password", role: :system_admin)
    @support_inquiry = SupportInquiry.create!(
      user: @user,
      category: :question,
      status: :not_started,
      subject: "Need help",
      reply_email: "reply@example.com",
      name_snapshot: "Customer Name",
      role_snapshot: "customer",
      last_message_at: Time.current,
      last_message_sender_kind: :user
    )
  end

  test "valid with required attributes" do
    assert build_message.valid?
  end

  test "required attributes must be present" do
    required_attributes = [
      :support_inquiry,
      :sender_user,
      :sender_kind,
      :body
    ]

    required_attributes.each do |attribute|
      message = build_message(attribute => nil)

      assert_not message.valid?, "#{attribute} should be required"
    end
  end

  test "sender kind enum works" do
    message = build_message(sender_kind: :user)
    assert message.sender_user?

    message.sender_kind = :system_admin
    assert message.sender_system_admin?
  end

  test "body has maximum length 5000" do
    assert build_message(body: "a" * 5_000).valid?

    message = build_message(body: "a" * 5_001)

    assert_not message.valid?
    assert message.errors.details[:body].any? { |detail| detail[:error] == :too_long }
  end

  test "associations connect support inquiry and sender user" do
    message = build_message(sender_user: @system_admin, sender_kind: :system_admin)
    message.save!

    assert_equal [ message ], @support_inquiry.support_inquiry_messages.to_a
    assert_equal [ message ], @system_admin.sent_support_inquiry_messages.to_a
  end

  private

  def build_message(attributes = {})
    SupportInquiryMessage.new(
      {
        support_inquiry: @support_inquiry,
        sender_user: @user,
        sender_kind: :user,
        body: "message"
      }.merge(attributes)
    )
  end
end
