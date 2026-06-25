# frozen_string_literal: true

require "test_helper"

class SupportInquiryMailerTest < ActionMailer::TestCase
  setup do
    @customer = User.create!(
      email: "support_inquiry_mail_customer@example.com",
      password: "password",
      role: :customer,
      display_name: "Mail Customer"
    )
    @system_admin = User.create!(email: "support_inquiry_mail_admin@example.com", password: "password", role: :system_admin)
    @support_inquiry = SupportInquiries::CreateService.new(
      user: @customer,
      attributes: {
        category: "question",
        subject: "Mail subject",
        reply_email: "reply-destination@example.com"
      },
      message_body: "Initial message"
    ).call.support_inquiry
    @support_inquiry_message = @support_inquiry.support_inquiry_messages.create!(
      sender_user: @system_admin,
      sender_kind: :system_admin,
      body: "Mailer reply body"
    )
  end

  test "reply email renders inquiry reply" do
    mail = SupportInquiryMailer
      .with(
        support_inquiry: @support_inquiry,
        support_inquiry_message: @support_inquiry_message
      )
      .reply

    assert_equal [ "reply-destination@example.com" ], mail.to
    assert_equal "【Butterflyve】お問い合わせに返信がありました", mail.subject
    assert_match "Mail Customer", mail.text_part.body.decoded
    assert_match "Mail subject", mail.text_part.body.decoded
    assert_match "Mailer reply body", mail.text_part.body.decoded
    assert_match "アプリ内のお問い合わせ画面から返信してください", mail.text_part.body.decoded
    assert_match "/support/inquiries/#{@support_inquiry.id}", mail.text_part.body.decoded
    assert_match "Mailer reply body", mail.html_part.body.decoded
  end
end
